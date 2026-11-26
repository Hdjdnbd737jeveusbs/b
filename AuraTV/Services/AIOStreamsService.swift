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
        while url.hasSuffix("/") { url = String(url.dropLast()) }
        if url.hasSuffix("/manifest.json") {
            url = String(url.dropLast("/manifest.json".count))
        }
        return url
    }

    var isLoading: Bool = false
    var streams: [StremioStream] = []
    var error: String?

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Manifest Validation

    func fetchManifest() async throws -> StremioManifest {
        guard !manifestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIOStreamsError.missingManifestURL
        }

        let manifestEndpoint = manifestURL.hasSuffix("/manifest.json")
            ? manifestURL
            : "\(baseURL)/manifest.json"

        guard let url = URL(string: manifestEndpoint) else {
            throw AIOStreamsError.invalidURL
        }

        let (data, response) = try await fetchData(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AIOStreamsError.httpError(statusCode: http.statusCode)
        }

        do {
            return try decoder.decode(StremioManifest.self, from: data)
        } catch {
            throw AIOStreamsError.decodingError(error)
        }
    }

    // MARK: - Fetch Streams (Raw Order Preserved)

    func fetchStreams(type: String, stremioId: String) async throws -> [StremioStream] {
        let urls = allManifestURLs
        guard !urls.isEmpty else {
            throw AIOStreamsError.missingManifestURL
        }

        var combined: [StremioStream] = []
        var firstError: Error?

        for manifest in urls {
            let root = Self.normalizedBaseURL(from: manifest)
            let endpoint = "\(root)/stream/\(type)/\(stremioId).json"
            guard let url = URL(string: endpoint) else {
                if firstError == nil { firstError = AIOStreamsError.invalidURL }
                continue
            }

            do {
                let (data, response) = try await fetchData(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    if firstError == nil { firstError = AIOStreamsError.httpError(statusCode: http.statusCode) }
                    continue
                }
                let result = try decoder.decode(StremioStreamResponse.self, from: data)
                if let items = result.streams {
                    combined.append(contentsOf: items)
                }
            } catch {
                if firstError == nil { firstError = (error as? AIOStreamsError) ?? AIOStreamsError.decodingError(error) }
            }
        }

        if combined.isEmpty, let firstError {
            throw firstError
        }
        return combined
    }

    // MARK: - High-Level: Movie & Series

    @MainActor
    func fetchStreamsForMovie(tmdbId: Int, preferredQuality: String = "4K") async throws -> [StremioStream] {
        isLoading = true
        error = nil
        streams = []
        defer { isLoading = false }

        let externalIds = try await TMDBService.shared.fetchMovieExternalIds(id: tmdbId)
        guard let imdbId = externalIds.imdbId, !imdbId.isEmpty else {
            throw AIOStreamsError.missingIMDbId
        }

        let result = try await fetchStreams(type: "movie", stremioId: imdbId)
        guard !result.isEmpty else {
            throw AIOStreamsError.noStreamsFound
        }

        // Preserve exact stream order returned by AIOStreams without re-sorting or hiding streams.
        streams = result
        return streams
    }

    @MainActor
    func fetchStreamsForEpisode(
        tmdbId: Int,
        season: Int,
        episode: Int,
        preferredQuality: String = "4K"
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
        let result = try await fetchStreams(type: "series", stremioId: stremioId)
        guard !result.isEmpty else {
            throw AIOStreamsError.noStreamsFound
        }

        // Preserve exact stream order returned by AIOStreams without re-sorting or hiding streams.
        streams = result
        return streams
    }

    // MARK: - Auto-Selection & Sorting

    /// Returns the best playable stream honoring `preferredQuality` ("4K", "1080p", "720p", "480p").
    func bestStream(matching preferredQuality: String, in candidates: [StremioStream]) -> StremioStream? {
        candidates
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
