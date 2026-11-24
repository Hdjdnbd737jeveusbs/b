import Foundation
import SwiftData

@Model
class WatchlistItem {
    var tmdbId: Int = 0
    var mediaType: String = "movie"
    var title: String = ""
    var posterPath: String?
    var backdropPath: String?
    var addedDate: Date = Date()

    // MARK: - Convenience Init

    convenience init(
        tmdbId: Int,
        mediaType: String,
        title: String,
        posterPath: String? = nil,
        backdropPath: String? = nil,
        addedDate: Date = Date()
    ) {
        self.init()
        self.tmdbId = tmdbId
        self.mediaType = mediaType
        self.title = title
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.addedDate = addedDate
    }
}
