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

// MARK: - Per-Episode Watched State Store (Spoiler Protection & Progress Sync)

enum EpisodeWatchedStore {
    private static func storageKey(tmdbId: Int) -> String {
        "auratv.watchedEpisodes.\(tmdbId)"
    }

    private static func token(season: Int, episode: Int) -> String {
        "S\(season)E\(episode)"
    }

    static func watchedTokens(tmdbId: Int) -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: storageKey(tmdbId: tmdbId)) ?? []
        return Set(arr)
    }

    static func isWatched(tmdbId: Int, season: Int, episode: Int) -> Bool {
        watchedTokens(tmdbId: tmdbId).contains(token(season: season, episode: episode))
    }

    static func markWatched(tmdbId: Int, season: Int, episode: Int, watched: Bool = true) {
        var set = watchedTokens(tmdbId: tmdbId)
        let key = token(season: season, episode: episode)
        if watched {
            set.insert(key)
        } else {
            set.remove(key)
        }
        UserDefaults.standard.set(Array(set), forKey: storageKey(tmdbId: tmdbId))
    }

    @discardableResult
    static func toggleWatched(tmdbId: Int, season: Int, episode: Int) -> Bool {
        let next = !isWatched(tmdbId: tmdbId, season: season, episode: episode)
        markWatched(tmdbId: tmdbId, season: season, episode: episode, watched: next)
        return next
    }
}

// MARK: - Remembered Playback Preferences (Audio Language + Series Addon / Quality)

struct SeriesPlaybackPreference: Codable, Sendable {
    var audioLanguage: String?
    var audioTrackNameHint: String?
    var preferredProvider: String?
    var preferredResolution: String?
    var subtitleLanguage: String?
    var updatedAt: Date = Date()
}

enum SeriesPlaybackPreferencesStore {
    private static let globalAudioKey = "auratv.global.preferredAudioLanguage"

    private static func key(for seriesId: Int) -> String {
        "auratv.seriesPreference.\(seriesId)"
    }

    static var globalPreferredAudioLanguage: String? {
        get { UserDefaults.standard.string(forKey: globalAudioKey) }
        set { UserDefaults.standard.set(newValue, forKey: globalAudioKey) }
    }

    static func load(seriesId: Int) -> SeriesPlaybackPreference? {
        guard seriesId > 0, let data = UserDefaults.standard.data(forKey: key(for: seriesId)) else {
            return nil
        }
        return try? JSONDecoder().decode(SeriesPlaybackPreference.self, from: data)
    }

    static func save(_ pref: SeriesPlaybackPreference, for seriesId: Int) {
        guard seriesId > 0 else { return }
        var updated = pref
        updated.updatedAt = Date()
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: key(for: seriesId))
        }
    }

    static func recordAudioChoice(seriesId: Int, mediaType: String, language: String?, trackName: String?) {
        let normalized = SubtitleLanguageMatcher.canonicalCode(from: language, fallbackName: trackName)
        if let normalized, !normalized.isEmpty {
            globalPreferredAudioLanguage = normalized
        }
        guard mediaType == "series", seriesId > 0 else { return }
        var pref = load(seriesId: seriesId) ?? SeriesPlaybackPreference()
        if let normalized, !normalized.isEmpty {
            pref.audioLanguage = normalized
        }
        if let trackName, !trackName.isEmpty {
            pref.audioTrackNameHint = trackName
        }
        save(pref, for: seriesId)
    }

    static func recordStreamChoice(seriesId: Int, mediaType: String, provider: String?, resolution: String?) {
        guard mediaType == "series", seriesId > 0 else { return }
        var pref = load(seriesId: seriesId) ?? SeriesPlaybackPreference()
        if let provider, !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pref.preferredProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let resolution, !resolution.isEmpty, resolution != "Unknown" {
            pref.preferredResolution = resolution
        }
        save(pref, for: seriesId)
    }
}

// MARK: - Smart Recent Searches Store

enum RecentSearchStore {
    private static let key = "auratv.recentSearches"
    private static let maxEntries = 8

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func add(_ query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return load() }
        var list = load().filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.insert(trimmed, at: 0)
        if list.count > maxEntries {
            list = Array(list.prefix(maxEntries))
        }
        UserDefaults.standard.set(list, forKey: key)
        return list
    }

    static func remove(_ query: String) -> [String] {
        let list = load().filter { $0.caseInsensitiveCompare(query) != .orderedSame }
        UserDefaults.standard.set(list, forKey: key)
        return list
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
