import Foundation
import SwiftData
import Observation

// MARK: - Export / Import Codable Model

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

    var tmdbApiKey: String = "d767cb12181edaa01840442c704329be"
    var aioStreamsUrl: String = ""
    var preferredQuality: String = "4K"
    var preferredLanguage: String = "en"
    var subtitleLanguage: String = "ar"
    var secondarySubtitleLanguage: String = "en"
    var subtitleAutoMode: String = "Preferred Languages"

    var subdlApiKey: String = ""
    var openSubtitlesApiKey: String = ""
    var subtitleFontSize: Double = 44.0
    var subtitleFontWeight: String = "Bold"
    var subtitleFontName: String = "System"
    var fixArabicRTL: Bool = true
    var fixReversedPunctuation: Bool = true
    var autoSyncSubtitles: Bool = false

    // Playback
    var resumePlaybackBehavior: String = "Ask"
    var nextEpisodeBehavior: String = "On · 10 s"
    var playerEngineName: String = "KSPlayer"
    var audioOutputMode: String = "Dolby Digital Plus 5.1"

    // Skip Intro & Credits
    var skipIntroMode: String = "Skip After Delay"
    var skipRecapMode: String = "Skip After Delay"
    var skipCreditsMode: String = "Show Button"
    var skipDelaySeconds: Int = 8
    var useIntroDB: Bool = true

    // Appearance & Artwork
    var homeHeroStyle: String = "Ambient"
    var moviesLayoutStyle: String = "Grid"
    var showWatchedIndicators: Bool = true
    var includeLogosInHome: Bool = true
    var preferredArtworkLanguage: String = "English"

    // Trakt
    var traktUsername: String = ""
    var traktScrobbleEnabled: Bool = true

    // Visual Ambient Banner
    var ambientBannerBackdropPath: String?

    var isSaving: Bool = false
    var exportData: Data?
    var statusMessage: String?
    var error: String?

    // MARK: - Static Option Lists

    static let qualityOptions = ["4K", "1080p", "720p", "480p"]
    static let homeLayoutOptions = ["Ambient", "Spotlight"]
    static let moviesLayoutOptions = ["Grid", "List"]
    static let resumeOptions = ["Ask", "Resume", "Start Over"]
    static let nextEpisodeOptions = ["On · 10 s", "On · 5 s", "Off"]
    static let playerEngineOptions = ["KSPlayer", "AVPlayer"]
    static let audioModeOptions = ["Dolby Digital Plus 5.1", "Stereo"]
    static let subtitleAutoOptions = ["Preferred Languages", "Always On", "Off"]
    static let subtitleSizeOptions: [Double] = [36, 44, 52, 58]
    static let fontWeightOptions = ["Regular", "Medium", "Semibold", "Bold"]
    static let fontNameOptions = ["System", "Geeza Pro", "SF Arabic", "Helvetica Neue"]
    static let skipModeOptions = ["Skip After Delay", "Show Button", "Off"]
    static let skipDelayOptions = [3, 5, 8, 10]
    static let artworkLanguageOptions = ["English", "Arabic", "All Languages"]

    static let languageOptions: [(code: String, name: String)] = [
        ("en", "English"),
        ("ar", "Arabic"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("pt", "Portuguese"),
        ("tr", "Turkish")
    ]

    func displayLanguageName(for code: String) -> String {
        Self.languageOptions.first(where: { $0.code == code })?.name ?? code.uppercased()
    }

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
                secondarySubtitleLanguage = settings.secondarySubtitleLanguage
                subtitleAutoMode = settings.subtitleAutoMode

                subdlApiKey = settings.subdlApiKey
                openSubtitlesApiKey = settings.openSubtitlesApiKey
                subtitleFontSize = settings.subtitleFontSize
                subtitleFontWeight = settings.subtitleFontWeight
                subtitleFontName = settings.subtitleFontName
                fixArabicRTL = settings.fixArabicRTL
                fixReversedPunctuation = settings.fixReversedPunctuation
                autoSyncSubtitles = settings.autoSyncSubtitles

                resumePlaybackBehavior = settings.resumePlaybackBehavior
                nextEpisodeBehavior = settings.nextEpisodeBehavior
                playerEngineName = settings.playerEngineName
                audioOutputMode = settings.audioOutputMode

                skipIntroMode = settings.skipIntroMode
                skipRecapMode = settings.skipRecapMode
                skipCreditsMode = settings.skipCreditsMode
                skipDelaySeconds = settings.skipDelaySeconds
                useIntroDB = settings.useIntroDB

                homeHeroStyle = settings.homeHeroStyle
                moviesLayoutStyle = settings.moviesLayoutStyle
                showWatchedIndicators = settings.showWatchedIndicators
                includeLogosInHome = settings.includeLogosInHome
                preferredArtworkLanguage = settings.preferredArtworkLanguage

                traktUsername = settings.traktUsername
                traktScrobbleEnabled = settings.traktScrobbleEnabled
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    func loadAmbientBannerIfNeeded() async {
        guard ambientBannerBackdropPath == nil else { return }
        if let trending = try? await TMDBService.shared.fetchTrendingMovies(page: 1),
           let firstBackdrop = trending.results.first(where: { $0.backdropPath != nil })?.backdropPath {
            ambientBannerBackdropPath = firstBackdrop
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
            settings.secondarySubtitleLanguage = secondarySubtitleLanguage
            settings.subtitleAutoMode = subtitleAutoMode

            settings.subdlApiKey = subdlApiKey
            settings.openSubtitlesApiKey = openSubtitlesApiKey
            settings.subtitleFontSize = subtitleFontSize
            settings.subtitleFontWeight = subtitleFontWeight
            settings.subtitleFontName = subtitleFontName
            settings.fixArabicRTL = fixArabicRTL
            settings.fixReversedPunctuation = fixReversedPunctuation
            settings.autoSyncSubtitles = autoSyncSubtitles

            settings.resumePlaybackBehavior = resumePlaybackBehavior
            settings.nextEpisodeBehavior = nextEpisodeBehavior
            settings.playerEngineName = playerEngineName
            settings.audioOutputMode = audioOutputMode

            settings.skipIntroMode = skipIntroMode
            settings.skipRecapMode = skipRecapMode
            settings.skipCreditsMode = skipCreditsMode
            settings.skipDelaySeconds = skipDelaySeconds
            settings.useIntroDB = useIntroDB

            settings.homeHeroStyle = homeHeroStyle
            settings.moviesLayoutStyle = moviesLayoutStyle
            settings.showWatchedIndicators = showWatchedIndicators
            settings.includeLogosInHome = includeLogosInHome
            settings.preferredArtworkLanguage = preferredArtworkLanguage

            settings.traktUsername = traktUsername
            settings.traktScrobbleEnabled = traktScrobbleEnabled

            try context.save()

            TMDBService.shared.apiKey = tmdbApiKey.isEmpty ? "d767cb12181edaa01840442c704329be" : tmdbApiKey
            AIOStreamsService.shared.manifestURL = aioStreamsUrl
            SubtitleService.shared.subdlApiKey = subdlApiKey
            SubtitleService.shared.openSubtitlesApiKey = openSubtitlesApiKey
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }

    // MARK: - Option Cycling Helper

    func nextValue<T: Equatable>(after current: T, in list: [T]) -> T {
        guard let idx = list.firstIndex(of: current) else {
            return list.first ?? current
        }
        return list[(idx + 1) % list.count]
    }

    // MARK: - Export / Import / Clear Watch History

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
            statusMessage = "Exported \(items.count) items to JSON."
            return data
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    @MainActor
    func importWatchHistory(data: Data, context: ModelContext) {
        error = nil

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let importedItems = try decoder.decode([WatchHistoryExport].self, from: data)
            for imported in importedItems {
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
            statusMessage = "Imported \(importedItems.count) items from backup."
        } catch {
            self.error = "Failed to import watch history: \(error.localizedDescription)"
        }
    }

    @MainActor
    func clearWatchHistory(context: ModelContext) {
        let descriptor = FetchDescriptor<WatchHistory>()
        do {
            let items = try context.fetch(descriptor)
            for item in items { context.delete(item) }
            try context.save()
            statusMessage = "Watch history cleared."
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    func clearWatchlist(context: ModelContext) {
        let descriptor = FetchDescriptor<WatchlistItem>()
        do {
            let items = try context.fetch(descriptor)
            for item in items { context.delete(item) }
            try context.save()
            statusMessage = "Watchlist cleared."
        } catch {
            self.error = error.localizedDescription
        }
    }
}
