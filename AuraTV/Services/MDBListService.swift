import Foundation
import Observation

// MARK: - MDBList Ratings Model

struct MDBListRatingsSummary: Codable, Equatable, Sendable {
    let imdb: Double?
    let rottenTomatoes: Int?
    let metacritic: Int?
    let letterboxd: Double?

    var isEmpty: Bool {
        imdb == nil && rottenTomatoes == nil && metacritic == nil && letterboxd == nil
    }
}

private struct CachedMDBListRecord: Codable {
    let timestamp: Date
    let summary: MDBListRatingsSummary
}

// MARK: - MDBList Service (With In-Memory & Disk Cache)

@Observable
final class MDBListService {
    static let shared = MDBListService()

    var apiKey: String = ""

    private let session: URLSession
    private let cacheDirectory: URL
    private var memoryCache: [String: CachedMDBListRecord] = [:]
    private let lock = NSLock()
    private let cacheTTL: TimeInterval = 24 * 60 * 60

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.cacheDirectory = caches.appendingPathComponent("AuraMDBList", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func fetchRatings(tmdbId: Int, mediaType: String) async -> MDBListRatingsSummary? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        let typeSlug = (mediaType == "series" || mediaType == "tv") ? "show" : "movie"
        let cacheKey = "\(typeSlug)_\(tmdbId)"

        if let cached = readCachedSummary(for: cacheKey) {
            return cached.isEmpty ? nil : cached
        }

        guard let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.mdblist.com/tmdb/\(typeSlug)/\(tmdbId)?apikey=\(encodedKey)") else {
            return nil
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }

            if let summary = Self.parseRatings(from: data) {
                writeCachedSummary(summary, for: cacheKey)
                return summary.isEmpty ? nil : summary
            }
        } catch {
            // Gracefully omit ratings when offline or API fails
        }

        return nil
    }

    // MARK: - Response Parsing

    private static func parseRatings(from data: Data) -> MDBListRatingsSummary? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let ratings = root["ratings"] as? [[String: Any]] else {
            return MDBListRatingsSummary(imdb: nil, rottenTomatoes: nil, metacritic: nil, letterboxd: nil)
        }

        var imdb: Double?
        var rottenTomatoes: Int?
        var metacritic: Int?
        var letterboxd: Double?

        for entry in ratings {
            let source = (entry["source"] as? String ?? "").lowercased()
            let val = numericDouble(entry["value"])
            let score = numericDouble(entry["score"])

            switch source {
            case "imdb":
                if let v = val, v > 0 {
                    imdb = v
                } else if let s = score, s > 0 {
                    imdb = s / 10.0
                }
            case "tomatoes", "rotten_tomatoes":
                let resolved = Int((val ?? score ?? 0).rounded())
                if resolved > 0 {
                    rottenTomatoes = resolved
                }
            case "metacritic":
                let resolved = Int((val ?? score ?? 0).rounded())
                if resolved > 0 {
                    metacritic = resolved
                }
            case "letterboxd":
                if let v = val, v > 0 {
                    letterboxd = v
                } else if let s = score, s > 0 {
                    letterboxd = s / 20.0
                }
            default:
                break
            }
        }

        return MDBListRatingsSummary(
            imdb: imdb,
            rottenTomatoes: rottenTomatoes,
            metacritic: metacritic,
            letterboxd: letterboxd
        )
    }

    private static func numericDouble(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    // MARK: - Local Caching

    private func readCachedSummary(for key: String) -> MDBListRatingsSummary? {
        let now = Date()

        lock.lock()
        let inMem = memoryCache[key]
        lock.unlock()

        if let inMem, now.timeIntervalSince(inMem.timestamp) < cacheTTL {
            return inMem.summary
        }

        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
        if let data = try? Data(contentsOf: fileURL),
           let disk = try? JSONDecoder().decode(CachedMDBListRecord.self, from: data),
           now.timeIntervalSince(disk.timestamp) < cacheTTL {
            lock.lock()
            memoryCache[key] = disk
            lock.unlock()
            return disk.summary
        }

        return nil
    }

    private func writeCachedSummary(_ summary: MDBListRatingsSummary, for key: String) {
        let record = CachedMDBListRecord(timestamp: Date(), summary: summary)

        lock.lock()
        memoryCache[key] = record
        lock.unlock()

        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
