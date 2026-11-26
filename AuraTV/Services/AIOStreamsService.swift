import Foundation
import CryptoKit
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

    var addons: [InstalledAddon] = (UserDefaults.standard.data(forKey: "installedAddons").flatMap {
        try? JSONDecoder().decode([InstalledAddon].self, from: $0)
    }) ?? [] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(addons), forKey: "installedAddons") }
    }

    var manifestURL: String = ""

    var baseURL: String {
        var url = manifestURL.trimmingCharacters(in: .whitespacesAndNewlines)
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

    // MARK: - Fetch Streams (Raw)

    @MainActor
    func fetchStreams(type: String, stremioId: String) async throws -> [StremioStream] {
        var endpoints: [URL] = []
        if !baseURL.isEmpty, let primary = URL(string: "\(baseURL)/stream/\(type)/\(stremioId).json") {
            endpoints.append(primary)
        }
        for addon in addons where addon.enabled && addon.supports("stream", type: type, id: stremioId) {
            let url = addon.url("stream", type, stremioId)
            if !endpoints.contains(url) { endpoints.append(url) }
        }
        guard !endpoints.isEmpty else { throw AIOStreamsError.missingManifestURL }
        var results: [StremioStream] = []
        var seen = Set<String>()
        var lastError: Error?
        var receivedResponse = false
        for url in endpoints {
            do {
                let page: StremioStreamResponse = try await readAddon(url)
                receivedResponse = true
                results += (page.streams ?? []).filter { seen.insert($0.id).inserted }
            } catch { lastError = error }
        }
        if !receivedResponse, let lastError { throw lastError }
        return results
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

        streams = sortedStreams(result, preferredQuality: preferredQuality)
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

        streams = sortedStreams(result, preferredQuality: preferredQuality)
        return streams
    }

    // MARK: - Auto-Selection & Sorting

    /// Returns the best playable stream honoring `preferredQuality` ("4K", "1080p", "720p", "480p").
    func bestStream(matching preferredQuality: String, in candidates: [StremioStream]) -> StremioStream? {
        candidates
            .first(where: { $0.url != nil && !($0.url?.isEmpty ?? true) })
    }

    func sortedStreams(_ streams: [StremioStream], preferredQuality: String = "4K") -> [StremioStream] {
        let prefs = UserDefaults.standard
        var rows = streams
        let hideCAM = prefs.bool(forKey: "hideCAM")
        let hide3D = prefs.bool(forKey: "hide3D")
        let hideDV = prefs.bool(forKey: "hideDV")
        if hideCAM || hide3D || hideDV {
            let filtered = rows.filter {
                let label = [$0.name, $0.title, $0.description, $0.behaviorHints?.filename].compactMap { $0 }.joined(separator: " ")
                let cam = hideCAM && label.range(of: #"(?i)\b(?:CAM|CAMRIP|HDCAM|TELESYNC)\b"#, options: .regularExpression) != nil
                let stereo = hide3D && label.range(of: #"(?i)\b3D\b"#, options: .regularExpression) != nil
                return !cam && !stereo && !(hideDV && $0.parsedInfo.hdrType == .dolbyVision)
            }
            if filtered.contains(where: { $0.url?.isEmpty == false }) { rows = filtered }
        }
        func rank(_ stream: StremioStream) -> Int {
            let label = [stream.name, stream.title, stream.description, stream.behaviorHints?.filename].compactMap { $0 }.joined(separator: " ")
            switch prefs.string(forKey: "streamOrder") {
            case "Arabic first": return ["عربي", "Arabic", "🇸🇦"].contains { label.localizedCaseInsensitiveContains($0) } ? 0 : 1
            case "Cached first": return stream.parsedInfo.isCached ? 0 : 1
            case "Preferred quality": return stream.parsedInfo.resolution.rawValue == preferredQuality ? 0 : 1
            default: return 0
            }
        }
        guard let order = prefs.string(forKey: "streamOrder"), order != "Provider order" else { return rows }
        return rows.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
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

extension AIOStreamsService {
    @MainActor
    func install(_ input: String) async throws {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.lowercased().hasPrefix("stremio://") { raw = "https://" + raw.dropFirst(10) }
        guard let endpoint = URL(string: raw), endpoint.scheme == "https", endpoint.host != nil,
              endpoint.lastPathComponent == "manifest.json" else { throw AIOStreamsError.invalidURL }
        let manifest: StremioManifest = try await readAddon(endpoint)
        guard manifest.id != nil, manifest.resources != nil else { throw URLError(.cannotParseResponse) }
        if !addons.contains(where: { $0.endpoint == endpoint }) {
            addons.append(InstalledAddon(endpoint: endpoint, manifest: manifest))
        }
    }

    func readAddon<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    @MainActor
    func fetchShelves() async -> [AddonShelf] {
        struct Response: Decodable { let metas: [AddonTitle] }
        var shelves: [AddonShelf] = []
        for addon in addons where addon.enabled {
            for catalog in addon.manifest.catalogs ?? [] {
                guard let type = catalog.type, ["movie", "series"].contains(type), let id = catalog.id else { continue }
                let url = addon.url("catalog", type, id)
                guard let page: Response = try? await readAddon(url) else { continue }
                let titles = page.metas.filter { $0.id.range(of: #"^tt[0-9]+$"#, options: .regularExpression) != nil }
                if !titles.isEmpty {
                    shelves.append(AddonShelf(id: url, name: addon.name + " · " + (catalog.name ?? id), type: type, titles: titles))
                }
            }
        }
        return shelves
    }

    @MainActor
    func addonSubtitles(type: String, id: String) async -> [SubtitleTrackItem] {
        struct Entry: Decodable { let url: URL; let lang: String }
        struct Response: Decodable { let subtitles: [Entry] }
        var tracks: [SubtitleTrackItem] = []
        for addon in addons where addon.enabled && addon.supports("subtitles", type: type, id: id) {
            guard let page: Response = try? await readAddon(addon.url("subtitles", type, id)) else { continue }
            for entry in page.subtitles where ["https", "http"].contains(entry.url.scheme ?? "") {
                let code = ["ara": "ar", "eng": "en"][entry.lang.lowercased()] ?? entry.lang.lowercased()
                let key = SHA256.hash(data: Data(entry.url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
                if tracks.contains(where: { $0.id == key }) { continue }
                tracks.append(SubtitleTrackItem(id: key, name: addon.name, language: code, languageCode: code,
                    source: .addon, downloadURL: entry.url, releaseInfo: addon.name, hearingImpaired: false,
                    isEmbedded: false, embeddedTrackId: nil))
            }
        }
        return tracks
    }
}
