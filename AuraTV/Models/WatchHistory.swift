import Foundation
import SwiftData

@Model
class WatchHistory {
    var tmdbId: Int = 0
    var mediaType: String = "movie"
    var title: String = ""
    var posterPath: String?
    var backdropPath: String?
    var currentTime: Double = 0
    var totalDuration: Double = 0
    var seasonNumber: Int?
    var episodeNumber: Int?
    var episodeTitle: String?
    var episodeStillPath: String?
    var lastWatched: Date = Date()
    var isCompleted: Bool = false

    // MARK: - Computed Properties

    /// Progress between 0 and 1.
    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return min(max(currentTime / totalDuration, 0), 1)
    }

    /// Remaining time formatted as "1h 43m" or "43m".
    var remainingTimeFormatted: String {
        let remaining = max(totalDuration - currentTime, 0)
        let totalMinutes = Int(remaining / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    // MARK: - Init

    init(
        tmdbId: Int = 0,
        mediaType: String = "movie",
        title: String = "",
        posterPath: String? = nil,
        backdropPath: String? = nil,
        currentTime: Double = 0,
        totalDuration: Double = 0,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil,
        episodeStillPath: String? = nil,
        lastWatched: Date = Date(),
        isCompleted: Bool = false
    ) {
        self.tmdbId = tmdbId
        self.mediaType = mediaType
        self.title = title
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.currentTime = currentTime
        self.totalDuration = totalDuration
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
        self.episodeStillPath = episodeStillPath
        self.lastWatched = lastWatched
        self.isCompleted = isCompleted
    }
}
