import Foundation
import Observation
import os

// MARK: - Errors

enum TMDBError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case httpError(statusCode: Int)
    case decodingError(Error)
    case networkError(Error)
    case noData

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "TMDB API key is not configured. Please set it in Settings."
        case .invalidURL:
            return "Invalid request URL."
        case .httpError(let code):
            return "Server returned HTTP \(code)."
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .noData:
            return "No data received from server."
        }
    }
}

// MARK: - TMDBService

@Observable
final class TMDBService {

    // MARK: Singleton

    static let shared = TMDBService()

    // MARK: Configuration

    private let baseURL = "https://api.themoviedb.org/3/"
    private let imageBaseURL = "https://image.tmdb.org/t/p/"

    /// The API key used for all requests. Set from AppSettings via the UI layer.
    /// Falls back to the built-in default key so the app works out of the box.
    var apiKey: String = "d767cb12181edaa01840442c704329be"

    // MARK: Private

    private static let logger = Logger(subsystem: "com.auratv.AuraTV", category: "TMDB")
    private let session: URLSession
    private let decoder: JSONDecoder
    private let cacheLock = NSLock()
    private var logoCache: [String: String] = [:]
    private var noLogoKeys: Set<String> = []

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Image Helper

    /// Build a full TMDB image URL.
    /// - Parameters:
    ///   - path: The path returned by the API (e.g. "/abc123.jpg").
    ///   - size: One of the documented size strings such as "w500" or "original".
    /// - Returns: A complete URL, or `nil` when `path` is nil or empty.
    func imageURL(path: String?, size: String = "w500") -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "\(imageBaseURL)\(size)\(path)")
    }

    // MARK: - Movies

    func fetchTrendingMovies(page: Int = 1) async throws -> TMDBResponse<TMDBMovie> {
        try await request(endpoint: "trending/movie/day", queryItems: [.init(name: "page", value: "\(page)")])
    }

    func fetchPopularMovies(page: Int = 1) async throws -> TMDBResponse<TMDBMovie> {
        try await request(endpoint: "movie/popular", queryItems: [.init(name: "page", value: "\(page)")])
    }

    func fetchTopRatedMovies(page: Int = 1) async throws -> TMDBResponse<TMDBMovie> {
        try await request(endpoint: "movie/top_rated", queryItems: [.init(name: "page", value: "\(page)")])
    }

    func fetchNowPlayingMovies(page: Int = 1) async throws -> TMDBResponse<TMDBMovie> {
        try await request(endpoint: "movie/now_playing", queryItems: [.init(name: "page", value: "\(page)")])
    }

    func fetchUpcomingMovies(page: Int = 1) async throws -> TMDBResponse<TMDBMovie> {
        try await request(endpoint: "movie/upcoming", queryItems: [.init(name: "page", value: "\(page)")])
    }

    func fetchMovieDetails(id: Int) async throws -> TMDBMovieDetail {
        try await request(
            endpoint: "movie/\(id)",
            queryItems: [.init(name: "append_to_response", value: "credits,release_dates")]
        )
    }

    // MARK: - Series

    func fetchTrendingSeries(page: Int = 1) async throws -> TMDBResponse<TMDBSeries> {
        try await request(endpoint: "trending/tv/day", queryItems: [.init(name: "page", value: "\(page)")])
    }

    func fetchPopularSeries(page: Int = 1) async throws -> TMDBResponse<TMDBSeries> {
        try await request(endpoint: "tv/popular", queryItems: [.init(name: "page", value: "\(page)")])
    }

    func fetchTopRatedSeries(page: Int = 1) async throws -> TMDBResponse<TMDBSeries> {
        try await request(endpoint: "tv/top_rated", queryItems: [.init(name: "page", value: "\(page)")])
    }

    func fetchAiringTodaySeries(page: Int = 1) async throws -> TMDBResponse<TMDBSeries> {
        try await request(endpoint: "tv/airing_today", queryItems: [.init(name: "page", value: "\(page)")])
    }

    func fetchOnTheAirSeries(page: Int = 1) async throws -> TMDBResponse<TMDBSeries> {
        try await request(endpoint: "tv/on_the_air", queryItems: [.init(name: "page", value: "\(page)")])
    }

    func fetchSeriesDetails(id: Int) async throws -> TMDBSeriesDetail {
        try await request(
            endpoint: "tv/\(id)",
            queryItems: [.init(name: "append_to_response", value: "credits,content_ratings")]
        )
    }

    func fetchSeasonDetails(seriesId: Int, seasonNumber: Int) async throws -> TMDBSeasonDetail {
        try await request(endpoint: "tv/\(seriesId)/season/\(seasonNumber)")
    }

    // MARK: - External IDs

    func fetchMovieExternalIds(id: Int) async throws -> TMDBExternalIds {
        try await request(endpoint: "movie/\(id)/external_ids")
    }

    func fetchSeriesExternalIds(id: Int) async throws -> TMDBExternalIds {
        try await request(endpoint: "tv/\(id)/external_ids")
    }

    // MARK: - Images & Title Logos

    /// Fetch available logos, backdrops, and posters for a movie or TV series.
    func fetchImages(mediaType: String, id: Int) async throws -> TMDBImagesResponse {
        let normalizedType = mediaType == "series" ? "tv" : mediaType
        return try await request(
            endpoint: "\(normalizedType)/\(id)/images",
            queryItems: [.init(name: "include_image_language", value: "en,null")]
        )
    }

    /// Fetch full multi-language artwork sets (posters, backdrops, logos) for ChangeArtworkView.
    func fetchAllArtwork(mediaType: String, id: Int) async throws -> TMDBImagesResponse {
        let normalizedType = mediaType == "series" ? "tv" : mediaType
        return try await request(
            endpoint: "\(normalizedType)/\(id)/images",
            queryItems: [.init(name: "include_image_language", value: "en,ar,null")]
        )
    }

    /// Returns the best raster (non-SVG) transparent TMDB logo path for display in UIImage/AsyncImage.
    func fetchBestLogoPath(mediaType: String, id: Int) async -> String? {
        let normalizedType = mediaType == "series" ? "tv" : mediaType
        let cacheKey = "\(normalizedType)-\(id)"

        cacheLock.lock()
        if let cached = logoCache[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        if noLogoKeys.contains(cacheKey) {
            cacheLock.unlock()
            return nil
        }
        cacheLock.unlock()

        do {
            let images = try await fetchImages(mediaType: normalizedType, id: id)
            let candidates = (images.logos ?? []).filter {
                let lower = $0.filePath.lowercased()
                return !lower.hasSuffix(".svg")
            }

            // Prefer English landscape logos first, then language-neutral raster logos
            let chosen = candidates.first(where: { $0.iso6391 == "en" && ($0.aspectRatio ?? 2.0) >= 1.1 })
                ?? candidates.first(where: { $0.iso6391 == "en" })
                ?? candidates.first(where: { $0.iso6391 == nil })
                ?? candidates.first

            cacheLock.lock()
            if let path = chosen?.filePath {
                logoCache[cacheKey] = path
            } else {
                noLogoKeys.insert(cacheKey)
            }
            cacheLock.unlock()

            return chosen?.filePath
        } catch {
            return nil
        }
    }

    // MARK: - Search

    func searchMulti(query: String, page: Int = 1) async throws -> TMDBSearchResponse {
        try await request(
            endpoint: "search/multi",
            queryItems: [
                .init(name: "query", value: query),
                .init(name: "page", value: "\(page)"),
                .init(name: "include_adult", value: "false")
            ]
        )
    }

    // MARK: - Generic Request

    private func request<T: Decodable>(
        endpoint: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        guard !apiKey.isEmpty else {
            throw TMDBError.missingAPIKey
        }

        guard var components = URLComponents(string: "\(baseURL)\(endpoint)") else {
            throw TMDBError.invalidURL
        }

        var items = queryItems
        items.append(URLQueryItem(name: "api_key", value: apiKey))
        components.queryItems = items

        guard let url = components.url else {
            throw TMDBError.invalidURL
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(from: url)
        } catch {
            Self.logger.error("Network error for \(endpoint, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw TMDBError.networkError(error)
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            Self.logger.error("HTTP \(httpResponse.statusCode) for \(endpoint, privacy: .public)")
            throw TMDBError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Self.logger.error("Decoding error for \(endpoint, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw TMDBError.decodingError(error)
        }
    }
}
