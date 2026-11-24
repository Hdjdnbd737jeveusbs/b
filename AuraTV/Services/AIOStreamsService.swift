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
            return "AIOStreams manifest URL is not configured. Please set it in Settings."
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

    // MARK: Singleton

    static let shared = AIOStreamsService()

    // MARK: Configuration

    /// The base manifest URL set from AppSettings (e.g. "https://addon.example.com/...")
    /// We strip `/manifest.json` if present to get the base path for stream requests.
    var manifestURL: String = ""

    /// Computed base URL without trailing `/manifest.json`
    var baseURL: String {
        var url = manifestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove trailing slash
        while url.hasSuffix("/") { url = String(url.dropLast()) }
        // Remove manifest.json suffix
        if url.hasSuffix("/manifest.json") {
            url = String(url.dropLast("/manifest.json".count))
        }
        return url
    }

    // MARK: State

    var isLoading: Bool = false
    var streams: [StremioStream] = []
    var error: String?

    // MARK: Private

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

    /// Fetch and validate the manifest is reachable and valid.
    func fetchManifest() async throws -> StremioManifest {
        guard !manifestURL.isEmpty else {
            throw AIOStreamsError.missingManifestURL
        }

        let manifestEndpoint: String
        if manifestURL.hasSuffix("/manifest.json") {
            manifestEndpoint = manifestURL
        } else {
            manifestEndpoint = "\(baseURL)/manifest.json"
        }

        guard let url = URL(string: manifestEndpoint) else {
            throw AIOStreamsError.invalidURL
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw AIOStreamsError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AIOStreamsError.httpError(statusCode: http.statusCode)
        }

        do {
            return try decoder.decode(StremioManifest.self, from: data)
        } catch {
            throw AIOStreamsError.decodingError(error)
        }
    }

    // MARK: - Fetch Streams (Raw)

    /// Fetch streams for a given Stremio-compatible type and ID.
    /// - Parameters:
    ///   - type: "movie" or "series"
    ///   - stremioId: IMDb ID for movies (e.g. "tt1234567"), or "tt1234567:S:E" for episodes
    func fetchStreams(type: String, stremioId: String) async throws -> [StremioStream] {
        guard !manifestURL.isEmpty else {
            throw AIOStreamsError.missingManifestURL
        }

        let endpoint = "\(baseURL)/stream/\(type)/\(stremioId).json"

        guard let url = URL(string: endpoint) else {
            throw AIOStreamsError.invalidURL
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw AIOStreamsError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AIOStreamsError.httpError(statusCode: http.statusCode)
        }

        do {
            let result = try decoder.decode(StremioStreamResponse.self, from: data)
            return result.streams ?? []
        } catch {
            throw AIOStreamsError.decodingError(error)
        }
    }

    // MARK: - High-Level: Fetch Streams for Movie

    /// Fetch streams for a movie given its TMDB ID.
    /// Internally resolves the IMDb ID via TMDB external_ids.
    @MainActor
    func fetchStreamsForMovie(tmdbId: Int) async throws -> [StremioStream] {
        isLoading = true
        error = nil
        streams = []

        defer { isLoading = false }

        // Get IMDb ID
        let externalIds = try await TMDBService.shared.fetchMovieExternalIds(id: tmdbId)
        guard let imdbId = externalIds.imdbId, !imdbId.isEmpty else {
            throw AIOStreamsError.missingIMDbId
        }

        let result = try await fetchStreams(type: "movie", stremioId: imdbId)
        if result.isEmpty {
            throw AIOStreamsError.noStreamsFound
        }

        streams = sortedStreams(result)
        return streams
    }

    // MARK: - High-Level: Fetch Streams for Episode

    /// Fetch streams for a series episode given TMDB series ID, season number, and episode number.
    /// Stremio format: `tt1234567:season:episode`
    @MainActor
    func fetchStreamsForEpisode(tmdbId: Int, season: Int, episode: Int) async throws -> [StremioStream] {
        isLoading = true
        error = nil
        streams = []

        defer { isLoading = false }

        // Get IMDb ID
        let externalIds = try await TMDBService.shared.fetchSeriesExternalIds(id: tmdbId)
        guard let imdbId = externalIds.imdbId, !imdbId.isEmpty else {
            throw AIOStreamsError.missingIMDbId
        }

        let stremioId = "\(imdbId):\(season):\(episode)"
        let result = try await fetchStreams(type: "series", stremioId: stremioId)
        if result.isEmpty {
            throw AIOStreamsError.noStreamsFound
        }

        streams = sortedStreams(result)
        return streams
    }

    // MARK: - Sorting

    /// Sort streams by quality: 4K first, then 1080p, 720p, etc.
    /// Within same resolution, cached streams first, then by file size descending.
    private func sortedStreams(_ streams: [StremioStream]) -> [StremioStream] {
        streams.sorted { a, b in
            let infoA = a.parsedInfo
            let infoB = b.parsedInfo

            if infoA.qualitySortOrder != infoB.qualitySortOrder {
                return infoA.qualitySortOrder < infoB.qualitySortOrder
            }

            // Cached first
            if infoA.isCached != infoB.isCached {
                return infoA.isCached
            }

            return false
        }
    }

    // MARK: - Grouping

    /// Group streams by resolution for the picker UI.
    func groupedByResolution() -> [(resolution: StreamResolution, streams: [StremioStream])] {
        let grouped = Dictionary(grouping: streams) { $0.parsedInfo.resolution }

        let order: [StreamResolution] = [.uhd4k, .fhd1080p, .hd720p, .sd480p, .unknown]
        return order.compactMap { resolution in
            guard let group = grouped[resolution], !group.isEmpty else { return nil }
            return (resolution: resolution, streams: group)
        }
    }
}
