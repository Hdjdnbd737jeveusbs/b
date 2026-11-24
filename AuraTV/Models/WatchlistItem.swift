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

    // MARK: - Init

    init(
        tmdbId: Int = 0,
        mediaType: String = "movie",
        title: String = "",
        posterPath: String? = nil,
        backdropPath: String? = nil,
        addedDate: Date = Date()
    ) {
        self.tmdbId = tmdbId
        self.mediaType = mediaType
        self.title = title
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.addedDate = addedDate
    }
}
