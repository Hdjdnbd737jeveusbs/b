import Foundation
import Observation

// MARK: - AIOStreams Service Errors

enum AIOStreamsError: LocalizedError {
    case missingManifestURL
    case invalidURL
    case missingIMDbId
    case httpError(statusCode: Int)
    case decodingError(Error)
    case networkError(Error)
    case noStreamsFound

    var errorDescription: String? {
        switch self {
        case .missingManifestURL:
            return "AIOStreams manifest URL is not configured. Please set it in Settings → Servers & Accounts."
        case .invalidURL:
            return "Invalid AIOStreams URL."
        case .missingIMDbId:
            return "Could not find IMDb ID for this title."
        case .httpError(let code):
            return "AIOStreams returned HTTP \(code)."
        case .decodingError(let error):
            return "Failed to parse streams: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .noStreamsFound:
            return "No streams found for this title."
        }
    }
}

// MARK: - AIOStreams Service

@Observable
final class AIOStreamsService {

    static let shared = AIOStreamsService()

    var manifestURL: String = ""
    var additionalManifestURLs: String = ""

    var combinedManifestInput: String {
        let extra = additionalManifestURLs.trimmingCharacters(in: .whitespacesAndNewlines)
        if extra.isEmpty { return manifestURL }
        if manifestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return extra }
        return "\(manifestURL)\n\(extra)"
    }

    var allManifestURLs: [String] {
        var seen = Set<String>()
        var result: [String] = []
        let rawList = ([manifestURL] + additionalManifestURLs.components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ","))))
        for item in rawList {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    var baseURL: String {
        Self.normalizedBaseURL(from: manifestURL)
    }

    private static func normalizedBaseURL(from rawURL: String) -> String {
        var url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.lowercased().hasPrefix("stremio://") {
            url = "https://" + String(url.dropFirst("stremio://".count))
        }
        while url.hasSuffix("/") { url = String(url.dropLast()) }
        if url.hasSuffix("/manifest.json") {
            url = String(url.dropLast("/manifest.json".count))
        }
        return url
    }

    static func normalizedManifestURL(from rawURL: String) -> String {
        let base = normalizedBaseURL(from: rawURL)
        guard !base.isEmpty else { return "" }
        return "\(base)/manifest.json"
    }

    var isLoading: Bool = false
    var streams: [StremioStream] = []
    var error: String?

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Manifest Validation

    func validateManifest(at rawURL: String) async throws -> (normalizedURL: String, manifest: StremioManifest) {
        let endpoint = Self.normalizedManifestURL(from: rawURL)
        guard !endpoint.isEmpty else {
            throw AIOStreamsError.missingManifestURL
        }
        guard let url = URL(string: endpoint),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            throw AIOStreamsError.invalidURL
        }

        let (data, response) = try await fetchData(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AIOStreamsError.httpError(statusCode: http.statusCode)
        }

        do {
            let manifest = try decoder.decode(StremioManifest.self, from: data)
            return (endpoint, manifest)
        } catch {
            throw AIOStreamsError.decodingError(error)
        }
    }

    func fetchManifest() async throws -> StremioManifest {
        try await validateManifest(at: manifestURL).manifest
    }

    // MARK: - Fetch Streams (Parallel + Off-MainActor Progressive Streaming)

    func fetchStreamsProgressive(
        type: String,
        stremioId: String,
        onPartialResults: (@MainActor ([StremioStream], Bool) -> Void)? = nil
    ) async throws -> [StremioStream] {
        let urls = allManifestURLs
        guard !urls.isEmpty else {
            throw AIOStreamsError.missingManifestURL
        }

        let urlSession = self.session

        // Decode & fetch concurrently off the MainActor so the tvOS UI stays locked at 60fps.
        let (finalStreams, firstError): ([StremioStream], Error?) = await Task.detached(priority: .userInitiated) {
            var resultsByIndex: [Int: [StremioStream]] = [:]
            var earliestError: Error?
            var completedCount = 0
            let totalCount = urls.count

            await withTaskGroup(of: (Int, [StremioStream]?, Error?).self) { group in
                for (index, manifest) in urls.enumerated() {
                    group.addTask {
                        let root = Self.normalizedBaseURL(from: manifest)
                        let endpoint = "\(root)/stream/\(type)/\(stremioId).json"
                        guard let url = URL(string: endpoint) else {
                            return (index, nil, AIOStreamsError.invalidURL)
                        }

                        do {
                            let (data, response) = try await urlSession.data(from: url)
                            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                                return (index, nil, AIOStreamsError.httpError(statusCode: http.statusCode))
                            }
                            let bgDecoder = JSONDecoder()
                            bgDecoder.keyDecodingStrategy = .convertFromSnakeCase
                            let decoded = try bgDecoder.decode(StremioStreamResponse.self, from: data)
                            return (index, decoded.streams ?? [], nil)
                        } catch let err as AIOStreamsError {
                            return (index, nil, err)
                        } catch {
                            return (index, nil, AIOStreamsError.decodingError(error))
                        }
                    }
                }

                for await (index, items, err) in group {
                    completedCount += 1
                    if let items {
                        resultsByIndex[index] = items
                    } else if let err, earliestError == nil {
                        earliestError = err
                    }

                    let orderedSoFar = (0..<totalCount).compactMap { resultsByIndex[$0] }.flatMap { $0 }
                    let isStillLoading = completedCount < totalCount
                    if let onPartialResults, !orderedSoFar.isEmpty {
                        await onPartialResults(orderedSoFar, isStillLoading)
                    }
                }
            }

            let orderedFinal = (0..<totalCount).compactMap { resultsByIndex[$0] }.flatMap { $0 }
            return (orderedFinal, earliestError)
        }.value

        if finalStreams.isEmpty, let firstError {
            throw firstError
        }
        return finalStreams
    }

    func fetchStreams(type: String, stremioId: String) async throws -> [StremioStream] {
        try await fetchStreamsProgressive(type: type, stremioId: stremioId)
    }

    // MARK: - High-Level: Movie & Series

    @MainActor
    func fetchStreamsProgressiveForMovie(
        tmdbId: Int,
        preferredQuality: String = "4K",
        onUpdate: @escaping @MainActor ([StremioStream], Bool) -> Void
    ) async throws -> [StremioStream] {
        isLoading = true
        error = nil
        streams = []
        defer { isLoading = false }

        let externalIds = try await TMDBService.shared.fetchMovieExternalIds(id: tmdbId)
        guard let imdbId = externalIds.imdbId, !imdbId.isEmpty else {
            throw AIOStreamsError.missingIMDbId
        }

        let result = try await fetchStreamsProgressive(type: "movie", stremioId: imdbId) { partial, stillLoading in
            self.streams = partial
            onUpdate(partial, stillLoading)
        }
        guard !result.isEmpty else {
            throw AIOStreamsError.noStreamsFound
        }

        streams = result
        return result
    }

    @MainActor
    func fetchStreamsProgressiveForEpisode(
        tmdbId: Int,
        season: Int,
        episode: Int,
        preferredQuality: String = "4K",
        onUpdate: @escaping @MainActor ([StremioStream], Bool) -> Void
    ) async throws -> [StremioStream] {
        isLoading = true
        error = nil
        streams = []
        defer { isLoading = false }

        let externalIds = try await TMDBService.shared.fetchSeriesExternalIds(id: tmdbId)
        guard let imdbId = externalIds.imdbId, !imdbId.isEmpty else {
            throw AIOStreamsError.missingIMDbId
        }

        let stremioId = "\(imdbId):\(season):\(episode)"
        let result = try await fetchStreamsProgressive(type: "series", stremioId: stremioId) { partial, stillLoading in
            self.streams = partial
            onUpdate(partial, stillLoading)
        }
        guard !result.isEmpty else {
            throw AIOStreamsError.noStreamsFound
        }

        streams = result
        return result
    }

    @MainActor
    func fetchStreamsForMovie(tmdbId: Int, preferredQuality: String = "4K") async throws -> [StremioStream] {
        try await fetchStreamsProgressiveForMovie(tmdbId: tmdbId, preferredQuality: preferredQuality) { _, _ in }
    }

    @MainActor
    func fetchStreamsForEpisode(
        tmdbId: Int,
        season: Int,
        episode: Int,
        preferredQuality: String = "4K"
    ) async throws -> [StremioStream] {
        try await fetchStreamsProgressiveForEpisode(
            tmdbId: tmdbId,
            season: season,
            episode: episode,
            preferredQuality: preferredQuality
        ) { _, _ in }
    }

    // MARK: - Auto-Selection & Sorting

    /// Returns the best playable stream honoring `preferredQuality` ("4K", "1080p", "720p", "480p").
    func bestStream(matching preferredQuality: String, in candidates: [StremioStream]) -> StremioStream? {
        sortedStreams(candidates, preferredQuality: preferredQuality)
            .first(where: { $0.url != nil && !($0.url?.isEmpty ?? true) })
    }

    func sortedStreams(_ streams: [StremioStream], preferredQuality: String = "4K") -> [StremioStream] {
        let targetRes = StreamResolution(rawValue: preferredQuality) ?? .uhd4k

        return streams.sorted { a, b in
            let infoA = a.parsedInfo
            let infoB = b.parsedInfo

            // 1. Exact preferred quality tier comes first
            let matchA = infoA.resolution == targetRes
            let matchB = infoB.resolution == targetRes
            if matchA != matchB {
                return matchA
            }

            // 2. Otherwise sort descending resolution order (4K -> 1080p -> 720p -> ...)
            if infoA.qualitySortOrder != infoB.qualitySortOrder {
                return infoA.qualitySortOrder < infoB.qualitySortOrder
            }

            // 3. Cached debrid streams first
            if infoA.isCached != infoB.isCached {
                return infoA.isCached
            }

            // 4. REMUX / HDR boost
            let remuxA = infoA.releaseType == "REMUX"
            let remuxB = infoB.releaseType == "REMUX"
            if remuxA != remuxB {
                return remuxA
            }

            return (infoA.hdrType != nil) && (infoB.hdrType == nil)
        }
    }

    func groupedByResolution() -> [(resolution: StreamResolution, streams: [StremioStream])] {
        let grouped = Dictionary(grouping: streams) { $0.parsedInfo.resolution }
        let order: [StreamResolution] = [.uhd4k, .fhd1080p, .hd720p, .sd480p, .unknown]
        return order.compactMap { resolution in
            guard let group = grouped[resolution], !group.isEmpty else { return nil }
            return (resolution: resolution, streams: group)
        }
    }

    // MARK: - Private Network Helper

    private func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: url)
        } catch {
            throw AIOStreamsError.networkError(error)
        }
    }
}
