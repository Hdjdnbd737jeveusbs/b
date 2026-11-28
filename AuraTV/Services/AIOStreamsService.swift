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
    private let cacheLock = NSLock()
    private var prefetchedStreamsCache: [String: (streams: [StremioStream], timestamp: Date)] = [:]
    private var cachedImdbByTmdbKey: [String: String] = [:]
    private let streamCacheTTL: TimeInterval = 480

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    private func cachedImdbId(for key: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedImdbByTmdbKey[key]
    }

    private func storeImdbId(_ imdbId: String, for key: String) {
        cacheLock.lock()
        cachedImdbByTmdbKey[key] = imdbId
        cacheLock.unlock()
    }

    private func cachedStreams(for cacheKey: String) -> [StremioStream]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let entry = prefetchedStreamsCache[cacheKey] else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > streamCacheTTL {
            prefetchedStreamsCache.removeValue(forKey: cacheKey)
            return nil
        }
        return entry.streams
    }

    private func storeStreams(_ streams: [StremioStream], for cacheKey: String) {
        cacheLock.lock()
        prefetchedStreamsCache[cacheKey] = (streams, Date())
        cacheLock.unlock()
    }

    func invalidatePrefetchCache() {
        cacheLock.lock()
        prefetchedStreamsCache.removeAll()
        cacheLock.unlock()
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
            let manifest = try await Task.detached(priority: .userInitiated) {
                let bgDecoder = JSONDecoder()
                bgDecoder.keyDecodingStrategy = .convertFromSnakeCase
                return try bgDecoder.decode(StremioManifest.self, from: data)
            }.value
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

    private func resolveMovieImdbId(tmdbId: Int) async throws -> String {
        let key = "movie-\(tmdbId)"
        if let hit = cachedImdbId(for: key) { return hit }
        let externalIds = try await TMDBService.shared.fetchMovieExternalIds(id: tmdbId)
        guard let imdbId = externalIds.imdbId, !imdbId.isEmpty else {
            throw AIOStreamsError.missingIMDbId
        }
        storeImdbId(imdbId, for: key)
        return imdbId
    }

    private func resolveSeriesImdbId(tmdbId: Int) async throws -> String {
        let key = "series-\(tmdbId)"
        if let hit = cachedImdbId(for: key) { return hit }
        let externalIds = try await TMDBService.shared.fetchSeriesExternalIds(id: tmdbId)
        guard let imdbId = externalIds.imdbId, !imdbId.isEmpty else {
            throw AIOStreamsError.missingIMDbId
        }
        storeImdbId(imdbId, for: key)
        return imdbId
    }

    func cachedPrefetchedMovieStreams(tmdbId: Int) -> [StremioStream]? {
        cachedStreams(for: "movie-\(tmdbId)")
    }

    func cachedPrefetchedEpisodeStreams(tmdbId: Int, season: Int, episode: Int) -> [StremioStream]? {
        cachedStreams(for: "series-\(tmdbId)-S\(season)E\(episode)")
    }

    /// Silently fetches and sorts movie streams in the background (never sets error/loading flags).
    @discardableResult
    func prefetchStreamsForMovie(
        tmdbId: Int,
        preferredQuality: String = "4K",
        preferredProvider: String? = nil
    ) async -> [StremioStream] {
        guard !allManifestURLs.isEmpty else { return [] }
        let cacheKey = "movie-\(tmdbId)"
        if let hit = cachedStreams(for: cacheKey), !hit.isEmpty {
            return hit
        }
        do {
            let imdbId = try await resolveMovieImdbId(tmdbId: tmdbId)
            let raw = try await fetchStreamsProgressive(type: "movie", stremioId: imdbId)
            let sorted = await Task.detached(priority: .utility) {
                Self.sortStreams(raw, preferredQuality: preferredQuality, preferredProvider: preferredProvider)
            }.value
            if !sorted.isEmpty {
                storeStreams(sorted, for: cacheKey)
            }
            return sorted
        } catch {
            return []
        }
    }

    /// Silently fetches and sorts episode streams in the background (never sets error/loading flags).
    @discardableResult
    func prefetchStreamsForEpisode(
        tmdbId: Int,
        season: Int,
        episode: Int,
        preferredQuality: String = "4K",
        preferredProvider: String? = nil
    ) async -> [StremioStream] {
        guard !allManifestURLs.isEmpty else { return [] }
        let cacheKey = "series-\(tmdbId)-S\(season)E\(episode)"
        if let hit = cachedStreams(for: cacheKey), !hit.isEmpty {
            return hit
        }
        do {
            let imdbId = try await resolveSeriesImdbId(tmdbId: tmdbId)
            let raw = try await fetchStreamsProgressive(type: "series", stremioId: "\(imdbId):\(season):\(episode)")
            let sorted = await Task.detached(priority: .utility) {
                Self.sortStreams(raw, preferredQuality: preferredQuality, preferredProvider: preferredProvider)
            }.value
            if !sorted.isEmpty {
                storeStreams(sorted, for: cacheKey)
            }
            return sorted
        } catch {
            return []
        }
    }

    @MainActor
    func fetchStreamsProgressiveForMovie(
        tmdbId: Int,
        preferredQuality: String = "4K",
        preferredProvider: String? = nil,
        bypassCache: Bool = false,
        onUpdate: @escaping @MainActor ([StremioStream], Bool) -> Void
    ) async throws -> [StremioStream] {
        let cacheKey = "movie-\(tmdbId)"
        if !bypassCache, let hit = cachedStreams(for: cacheKey), !hit.isEmpty {
            streams = hit
            onUpdate(hit, false)
            return hit
        }

        isLoading = true
        error = nil
        streams = []
        defer { isLoading = false }

        let imdbId = try await resolveMovieImdbId(tmdbId: tmdbId)

        let rawResult = try await fetchStreamsProgressive(type: "movie", stremioId: imdbId) { partial, stillLoading in
            let sortedPartial = Self.sortStreams(partial, preferredQuality: preferredQuality, preferredProvider: preferredProvider)
            self.streams = sortedPartial
            onUpdate(sortedPartial, stillLoading)
        }
        let result = await Task.detached(priority: .userInitiated) {
            Self.sortStreams(rawResult, preferredQuality: preferredQuality, preferredProvider: preferredProvider)
        }.value
        guard !result.isEmpty else {
            throw AIOStreamsError.noStreamsFound
        }

        storeStreams(result, for: cacheKey)
        streams = result
        return result
    }

    @MainActor
    func fetchStreamsProgressiveForEpisode(
        tmdbId: Int,
        season: Int,
        episode: Int,
        preferredQuality: String = "4K",
        preferredProvider: String? = nil,
        bypassCache: Bool = false,
        onUpdate: @escaping @MainActor ([StremioStream], Bool) -> Void
    ) async throws -> [StremioStream] {
        let cacheKey = "series-\(tmdbId)-S\(season)E\(episode)"
        if !bypassCache, let hit = cachedStreams(for: cacheKey), !hit.isEmpty {
            streams = hit
            onUpdate(hit, false)
            return hit
        }

        isLoading = true
        error = nil
        streams = []
        defer { isLoading = false }

        let imdbId = try await resolveSeriesImdbId(tmdbId: tmdbId)

        let stremioId = "\(imdbId):\(season):\(episode)"
        let rawResult = try await fetchStreamsProgressive(type: "series", stremioId: stremioId) { partial, stillLoading in
            let sortedPartial = Self.sortStreams(partial, preferredQuality: preferredQuality, preferredProvider: preferredProvider)
            self.streams = sortedPartial
            onUpdate(sortedPartial, stillLoading)
        }
        let result = await Task.detached(priority: .userInitiated) {
            Self.sortStreams(rawResult, preferredQuality: preferredQuality, preferredProvider: preferredProvider)
        }.value
        guard !result.isEmpty else {
            throw AIOStreamsError.noStreamsFound
        }

        storeStreams(result, for: cacheKey)
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

    // MARK: - Auto-Selection & Off-MainActor Sorting

    /// Returns the best playable stream honoring `preferredProvider` and `preferredQuality`.
    nonisolated func bestStream(matching preferredQuality: String, preferredProvider: String? = nil, in candidates: [StremioStream]) -> StremioStream? {
        Self.sortStreams(candidates, preferredQuality: preferredQuality, preferredProvider: preferredProvider)
            .first(where: { $0.url != nil && !($0.url?.isEmpty ?? true) })
    }

    nonisolated func sortedStreams(_ streams: [StremioStream], preferredQuality: String = "4K") -> [StremioStream] {
        Self.sortStreams(streams, preferredQuality: preferredQuality, preferredProvider: nil)
    }

    nonisolated static func sortStreams(
        _ streams: [StremioStream],
        preferredQuality: String = "4K",
        preferredProvider: String? = nil
    ) -> [StremioStream] {
        let targetRes = StreamResolution(rawValue: preferredQuality) ?? .uhd4k
        let normalizedProvider = preferredProvider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return streams.sorted { a, b in
            let infoA = a.parsedInfo
            let infoB = b.parsedInfo

            // 1. Remembered series addon/provider match comes first when configured
            if let normalizedProvider, !normalizedProvider.isEmpty {
                let provA = infoA.providerName?.lowercased() == normalizedProvider
                let provB = infoB.providerName?.lowercased() == normalizedProvider
                if provA != provB {
                    return provA
                }
            }

            // 2. Exact preferred quality tier
            let matchA = infoA.resolution == targetRes
            let matchB = infoB.resolution == targetRes
            if matchA != matchB {
                return matchA
            }

            // 3. Otherwise sort descending resolution order (4K -> 1080p -> 720p -> ...)
            if infoA.qualitySortOrder != infoB.qualitySortOrder {
                return infoA.qualitySortOrder < infoB.qualitySortOrder
            }

            // 4. Cached debrid streams first
            if infoA.isCached != infoB.isCached {
                return infoA.isCached
            }

            // 5. REMUX / HDR boost
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
