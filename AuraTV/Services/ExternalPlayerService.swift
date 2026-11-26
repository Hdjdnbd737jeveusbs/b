import Foundation
import UIKit

// MARK: - External Player Handoff & Resume Helper

enum ExternalPlayerService {

    /// Builds a deep-link URL to hand off playback to an external tvOS player.
    static func handoffURL(for playerName: String, streamURL: URL, title: String? = nil) -> URL? {
        switch playerName {
        case "Infuse":
            var components = URLComponents(string: "infuse://x-callback-url/play")
            components?.queryItems = [
                URLQueryItem(name: "url", value: streamURL.absoluteString)
            ]
            return components?.url

        case "VidHub":
            var components = URLComponents(string: "vidhub://x-callback-url/open")
            components?.queryItems = [
                URLQueryItem(name: "url", value: streamURL.absoluteString)
            ]
            return components?.url

        case "VLC":
            var components = URLComponents(string: "vlc-x-callback://x-callback-url/stream")
            var items = [URLQueryItem(name: "url", value: streamURL.absoluteString)]
            if let title, !title.isEmpty {
                items.append(URLQueryItem(name: "filename", value: title))
            }
            components?.queryItems = items
            return components?.url

        case "SenPlayer":
            var components = URLComponents(string: "senplayer://x-callback-url/play")
            components?.queryItems = [
                URLQueryItem(name: "url", value: streamURL.absoluteString)
            ]
            return components?.url

        default:
            return nil
        }
    }

    /// Attempts to open the configured external player with the given stream URL.
    /// Calls `completion(true)` if handoff succeeded, or `completion(false)` to proceed with built-in playback.
    @MainActor
    static func openExternalPlayerIfConfigured(
        playerName: String,
        streamURL: URL,
        title: String,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard let targetURL = handoffURL(for: playerName, streamURL: streamURL, title: title) else {
            completion(false)
            return
        }

        guard UIApplication.shared.canOpenURL(targetURL) else {
            completion(false)
            return
        }

        UIApplication.shared.open(targetURL, options: [:]) { success in
            Task { @MainActor in
                completion(success)
            }
        }
    }

    /// Computes resume timestamp honoring Start Over behavior and Rewind-on-Resume seconds.
    static func adjustedResumeTime(rawTime: Double, behavior: String, rewindSeconds: Int) -> Double {
        if behavior == "Start Over" {
            return 0
        }
        guard rawTime > 0 else { return 0 }
        return max(0, rawTime - Double(max(0, rewindSeconds)))
    }
}
