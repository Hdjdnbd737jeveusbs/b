import Foundation
import SwiftUI
import AVFoundation
import UIKit

// MARK: - TMDB Trailer Metadata & Muted Preview Service

struct TrailerLookupResult: Sendable {
    let videoKey: String
    let videoName: String
    let playableStreamURL: URL?
}

actor TrailerPreviewService {
    static let shared = TrailerPreviewService()

    private let session: URLSession
    private var cache: [String: TrailerLookupResult] = [:]
    private var missKeys: Set<String> = []

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4.5
        config.timeoutIntervalForResource = 6.0
        self.session = URLSession(configuration: config)
    }

    func fetchTrailer(mediaType: String, tmdbId: Int) async -> TrailerLookupResult? {
        let cacheKey = "\(mediaType)-\(tmdbId)"
        if let hit = cache[cacheKey] {
            return hit
        }
        if missKeys.contains(cacheKey) {
            return nil
        }

        do {
            let resp = try await TMDBService.shared.fetchVideos(mediaType: mediaType, id: tmdbId)
            let videos = resp.results ?? []

            let preferred =
                videos.first(where: { ($0.site ?? "") == "YouTube" && ($0.type ?? "") == "Trailer" && ($0.official ?? false) }) ??
                videos.first(where: { ($0.site ?? "") == "YouTube" && ($0.type ?? "") == "Trailer" }) ??
                videos.first(where: { ($0.site ?? "") == "YouTube" && ($0.type ?? "") == "Teaser" }) ??
                videos.first

            guard let selected = preferred, !selected.key.isEmpty else {
                missKeys.insert(cacheKey)
                return nil
            }

            let streamURL = await resolvePlayableStreamURL(youtubeKey: selected.key)
            let result = TrailerLookupResult(
                videoKey: selected.key,
                videoName: selected.name ?? "Trailer",
                playableStreamURL: streamURL
            )
            cache[cacheKey] = result
            return result
        } catch {
            return nil
        }
    }

    private func resolvePlayableStreamURL(youtubeKey: String) async -> URL? {
        let pipedMirrors = [
            "https://pipedapi.kavin.rocks/streams/\(youtubeKey)",
            "https://pipedapi.adminforge.de/streams/\(youtubeKey)"
        ]

        for mirror in pipedMirrors {
            guard let url = URL(string: mirror) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 3.5

            guard let (data, response) = try? await session.data(for: req),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let hls = json["hls"] as? String, let hlsURL = URL(string: hls) {
                return hlsURL
            }

            if let videoStreams = json["videoStreams"] as? [[String: Any]] {
                let candidate = videoStreams.first(where: {
                    let videoOnly = ($0["videoOnly"] as? Bool) ?? false
                    let mime = ($0["mimeType"] as? String ?? "").lowercased()
                    return !videoOnly && mime.contains("mp4") && ($0["url"] as? String) != nil
                }) ?? videoStreams.first(where: {
                    ($0["mimeType"] as? String ?? "").lowercased().contains("mp4") && ($0["url"] as? String) != nil
                })

                if let rawUrl = candidate?["url"] as? String, let mp4URL = URL(string: rawUrl) {
                    return mp4URL
                }
            }
        }

        return nil
    }
}

// MARK: - Muted Looping Inline Video Preview Layer (Zero HUD Chrome)

struct AuraMutedTrailerVideoView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let view = PlayerLayerUIView()
        context.coordinator.configure(url: url, on: view)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        context.coordinator.configure(url: url, on: uiView)
    }

    static func dismantleUIView(_ uiView: PlayerLayerUIView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class PlayerLayerUIView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    @MainActor
    final class Coordinator {
        private var currentURL: URL?
        private var looper: AVPlayerLooper?
        private var queuePlayer: AVQueuePlayer?

        func configure(url: URL, on view: PlayerLayerUIView) {
            if currentURL == url, queuePlayer != nil {
                view.playerLayer.player = queuePlayer
                view.playerLayer.videoGravity = .resizeAspectFill
                return
            }

            teardown()
            currentURL = url

            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = true
            player.volume = 0
            player.actionAtItemEnd = .none

            self.looper = AVPlayerLooper(player: player, templateItem: item)
            self.queuePlayer = player

            view.playerLayer.player = player
            view.playerLayer.videoGravity = .resizeAspectFill
            player.play()
        }

        func teardown() {
            queuePlayer?.pause()
            looper?.disableLooping()
            looper = nil
            queuePlayer = nil
            currentURL = nil
        }
    }
}
