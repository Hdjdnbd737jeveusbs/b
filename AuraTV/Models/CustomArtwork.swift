import Foundation
import SwiftData

@Model
class CustomArtwork {
    @Attribute(.unique) var key: String = ""
    var tmdbId: Int = 0
    var mediaType: String = "movie"
    var customPosterPath: String?
    var customBackdropPath: String?
    var customLogoPath: String?
    var multipleArtworkEnabled: Bool = false
    var rotationPosters: [String] = []
    var rotationBackdrops: [String] = []
    var updatedAt: Date = Date()

    func poster(at date: Date) -> String? {
        rotatedPath(rotationPosters, at: date) ?? customPosterPath
    }

    func backdrop(at date: Date) -> String? {
        rotatedPath(rotationBackdrops, at: date) ?? customBackdropPath
    }

    private func rotatedPath(_ paths: [String], at date: Date) -> String? {
        guard multipleArtworkEnabled, !paths.isEmpty else { return nil }
        let interval = Int(max(0, date.timeIntervalSince(updatedAt)) / 300)
        return paths[interval % paths.count]
    }

    static func makeKey(tmdbId: Int, mediaType: String) -> String {
        let normalized = mediaType == "tv" ? "series" : mediaType
        return "\(normalized)-\(tmdbId)"
    }

    init(
        key: String = "",
        tmdbId: Int = 0,
        mediaType: String = "movie",
        customPosterPath: String? = nil,
        customBackdropPath: String? = nil,
        customLogoPath: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.key = key.isEmpty ? Self.makeKey(tmdbId: tmdbId, mediaType: mediaType) : key
        self.tmdbId = tmdbId
        self.mediaType = mediaType == "tv" ? "series" : mediaType
        self.customPosterPath = customPosterPath
        self.customBackdropPath = customBackdropPath
        self.customLogoPath = customLogoPath
        self.updatedAt = updatedAt
    }
}
