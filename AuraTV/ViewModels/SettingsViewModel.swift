import Foundation
import SwiftData
import Observation

// MARK: - Export / Import Codable Model

/// Lightweight Codable representation of WatchHistory for JSON export/import.
private struct WatchHistoryExport: Codable {
    let tmdbId: Int
    let mediaType: String
    let title: String
    let posterPath: String?
    let backdropPath: String?
    let currentTime: Double
    let totalDuration: Double
    let seasonNumber: Int?
    let episodeNumber: Int?
    let episodeTitle: String?
    let episodeStillPath: String?
    let lastWatched: Date
    let isCompleted: Bool
}

@Observable
final class SettingsViewModel {

    // MARK: - Published State

    var tmdbApiKey: String = ""
    var aioStreamsUrl: String = ""
    var preferredQuality: String = "4K"
    var preferredLanguage: String = "en"
    var subtitleLanguage: String = "ar"
    var subdlApiKey: String = ""
    var openSubtitlesApiKey: String = ""
    var fixArabicRTL: Bool = true
    var fixReversedPunctuation: Bool = true
    var isSaving: Bool = false
    var exportData: Data?
    var error: String?

    static let qualityOptions = ["4K", "1080p", "720p", "480p"]
    static let languageOptions = [
        "en": "English",
        "ar": "Arabic",
        "es": "Spanish",
        "fr": "French",
        "de": "German",
        "it": "Italian",
        "ja": "Japanese",
        "ko": "Korean",
        "pt": "Portuguese",
        "zh": "Chinese",
        "hi": "Hindi",
        "ru": "Russian",
        "tr": "Turkish"
    ]

    // MARK: - Load Settings

    @MainActor
    func loadSettings(context: ModelContext) {
        let descriptor = FetchDescriptor<AppSettings>(
            predicate: #Predicate<AppSettings> { settings in
                settings.id == "default"
            }
        )

        do {
            let results = try context.fetch(descriptor)
            if let settings = results.first {
                tmdbApiKey = settings.tmdbApiKey
                aioStreamsUrl = settings.aioStreamsUrl
                preferredQuality = settings.preferredQuality
                preferredLanguage = settings.preferredLanguage
                subtitleLanguage = settings.subtitleLanguage
                subdlApiKey = settings.subdlApiKey
                openSubtitlesApiKey = settings.openSubtitlesApiKey
                fixArabicRTL = settings.fixArabicRTL
                fixReversedPunctuation = settings.fixReversedPunctuation
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Save Settings

    @MainActor
    func saveSettings(context: ModelContext) {
        isSaving = true
        error = nil

        let descriptor = FetchDescriptor<AppSettings>(
            predicate: #Predicate<AppSettings> { settings in
                settings.id == "default"
            }
        )

        do {
            let results = try context.fetch(descriptor)
            let settings: AppSettings

            if let existing = results.first {
                settings = existing
            } else {
                settings = AppSettings()
                context.insert(settings)
            }

            settings.tmdbApiKey = tmdbApiKey
            settings.aioStreamsUrl = aioStreamsUrl
            settings.preferredQuality = preferredQuality
            settings.preferredLanguage = preferredLanguage
            settings.subtitleLanguage = subtitleLanguage
            settings.subdlApiKey = subdlApiKey
            settings.openSubtitlesApiKey = openSubtitlesApiKey
            settings.fixArabicRTL = fixArabicRTL
            settings.fixReversedPunctuation = fixReversedPunctuation

            try context.save()

            // Update shared services
            TMDBService.shared.apiKey = tmdbApiKey
            AIOStreamsService.shared.manifestURL = aioStreamsUrl
            SubtitleService.shared.subdlApiKey = subdlApiKey
            SubtitleService.shared.openSubtitlesApiKey = openSubtitlesApiKey
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }

    // MARK: - Export Watch History

    @MainActor
    func exportWatchHistory(context: ModelContext) -> Data? {
        let descriptor = FetchDescriptor<WatchHistory>(
            sortBy: [SortDescriptor(\.lastWatched, order: .reverse)]
        )

        do {
            let items = try context.fetch(descriptor)

            let exportItems = items.map { item in
                WatchHistoryExport(
                    tmdbId: item.tmdbId,
                    mediaType: item.mediaType,
                    title: item.title,
                    posterPath: item.posterPath,
                    backdropPath: item.backdropPath,
                    currentTime: item.currentTime,
                    totalDuration: item.totalDuration,
                    seasonNumber: item.seasonNumber,
                    episodeNumber: item.episodeNumber,
                    episodeTitle: item.episodeTitle,
                    episodeStillPath: item.episodeStillPath,
                    lastWatched: item.lastWatched,
                    isCompleted: item.isCompleted
                )
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(exportItems)
            exportData = data
            return data
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    // MARK: - Import Watch History

    @MainActor
    func importWatchHistory(data: Data, context: ModelContext) {
        error = nil

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let importedItems = try decoder.decode([WatchHistoryExport].self, from: data)

            for imported in importedItems {
                // Check if entry already exists to avoid duplicates
                let tmdbId = imported.tmdbId
                let mediaType = imported.mediaType
                let descriptor = FetchDescriptor<WatchHistory>(
                    predicate: #Predicate<WatchHistory> { item in
                        item.tmdbId == tmdbId && item.mediaType == mediaType
                    }
                )

                let existing = try context.fetch(descriptor)

                let history: WatchHistory
                if let found = existing.first {
                    // Update existing entry if imported is newer
                    guard imported.lastWatched > found.lastWatched else { continue }
                    history = found
                } else {
                    history = WatchHistory()
                    context.insert(history)
                }

                history.tmdbId = imported.tmdbId
                history.mediaType = imported.mediaType
                history.title = imported.title
                history.posterPath = imported.posterPath
                history.backdropPath = imported.backdropPath
                history.currentTime = imported.currentTime
                history.totalDuration = imported.totalDuration
                history.seasonNumber = imported.seasonNumber
                history.episodeNumber = imported.episodeNumber
                history.episodeTitle = imported.episodeTitle
                history.episodeStillPath = imported.episodeStillPath
                history.lastWatched = imported.lastWatched
                history.isCompleted = imported.isCompleted
            }

            try context.save()
        } catch {
            self.error = "Failed to import watch history: \(error.localizedDescription)"
        }
    }

    // MARK: - Clear Watch History

    @MainActor
    func clearWatchHistory(context: ModelContext) {
        let descriptor = FetchDescriptor<WatchHistory>()

        do {
            let items = try context.fetch(descriptor)
            for item in items {
                context.delete(item)
            }
            try context.save()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Clear Watchlist

    @MainActor
    func clearWatchlist(context: ModelContext) {
        let descriptor = FetchDescriptor<WatchlistItem>()

        do {
            let items = try context.fetch(descriptor)
            for item in items {
                context.delete(item)
            }
            try context.save()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
