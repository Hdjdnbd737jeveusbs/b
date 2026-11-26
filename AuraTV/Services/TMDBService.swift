import Foundation
import Observation
import os
#if canImport(UIKit)
import UIKit
#endif
import CoreGraphics

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
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
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

    private func readCachedLogo(for key: String) -> (found: Bool, path: String?) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = logoCache[key] {
            return (true, cached)
        }
        if noLogoKeys.contains(key) {
            return (true, nil)
        }
        return (false, nil)
    }

    private func writeCachedLogo(_ path: String?, for key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let path {
            logoCache[key] = path
        } else {
            noLogoKeys.insert(key)
        }
    }

    /// Returns the best raster (non-SVG) transparent TMDB logo path that is visible on a dark canvas.
    func fetchBestLogoPath(mediaType: String, id: Int) async -> String? {
        let normalizedType = mediaType == "series" ? "tv" : mediaType
        let cacheKey = "\(normalizedType)-\(id)"

        let cached = readCachedLogo(for: cacheKey)
        if cached.found {
            return cached.path
        }

        do {
            let images = try await fetchImages(mediaType: normalizedType, id: id)
            let candidates = (images.logos ?? []).filter {
                let lower = $0.filePath.lowercased()
                return !lower.hasSuffix(".svg")
            }

            // Order preferred English landscape logos first, then neutral raster logos
            var ordered: [TMDBImageAsset] = []
            ordered.append(contentsOf: candidates.filter { $0.iso6391 == "en" && ($0.aspectRatio ?? 2.0) >= 1.1 })
            for asset in candidates where !ordered.contains(where: { $0.filePath == asset.filePath }) {
                ordered.append(asset)
            }

            // Pick the first candidate whose opaque pixels aren't dark ink on dark backgrounds.
            var selectedPath = ordered.first?.filePath
            for asset in ordered.prefix(5) {
                if let lum = await measureLogoLuminance(path: asset.filePath), lum >= 0.35 {
                    selectedPath = asset.filePath
                    break
                }
            }

            writeCachedLogo(selectedPath, for: cacheKey)
            return selectedPath
        } catch {
            return nil
        }
    }

    /// Computes average perceived luminance of non-transparent pixels in a w300 logo preview.
    private func measureLogoLuminance(path: String) async -> Double? {
        guard let url = imageURL(path: path, size: "w300"),
              let (data, _) = try? await session.data(from: url) else {
            return nil
        }
        #if canImport(UIKit)
        guard let cgImage = UIImage(data: data)?.cgImage else { return nil }
        let width = min(cgImage.width, 64)
        let height = min(cgImage.height, 32)
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var lumSum: Double = 0
        var opaqueCount: Int = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[i + 3])
            guard alpha > 32 else { continue }
            let a = Double(alpha) / 255.0
            let r = min(Double(pixels[i]) / 255.0 / a, 1.0)
            let g = min(Double(pixels[i + 1]) / 255.0 / a, 1.0)
            let b = min(Double(pixels[i + 2]) / 255.0 / a, 1.0)
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            lumSum += lum
            opaqueCount += 1
        }
        guard opaqueCount > 0 else { return nil }
        return lumSum / Double(opaqueCount)
        #else
        return nil
        #endif
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

extension TMDBService {
    func resolveIMDb(_ id: String, type: String) async throws -> Int {
        struct Hit: Decodable { let id: Int }
        struct Matches: Decodable { let movieResults: [Hit]; let tvResults: [Hit] }
        let found: Matches = try await request(endpoint: "find/" + id,
            queryItems: [.init(name: "external_source", value: "imdb_id")])
        guard let hit = (type == "movie" ? found.movieResults : found.tvResults).first else { throw TMDBError.noData }
        return hit.id
    }
}
