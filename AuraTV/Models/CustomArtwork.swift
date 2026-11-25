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
    var updatedAt: Date = Date()

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
