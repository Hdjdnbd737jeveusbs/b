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
    var aioStreamsAdditionalUrls: String = ""
    var quickManifestInput: String = ""
    var mdblistApiKey: String = ""
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
    var subtitleTextColor: String = "Light Gray"
    var subtitleTextOpacity: Double = 0.80
    var subtitleBackgroundOpacity: Double = 0.0
    var subtitleBottomOffset: Double = 56.0
    var fixArabicRTL: Bool = true
    var fixReversedPunctuation: Bool = true
    var autoSyncSubtitles: Bool = false

    // AI Live Subtitle Translation
    var aiTranslationEnabled: Bool = false
    var aiTranslationProvider: String = "OpenAI"
    var aiTranslationApiKey: String = ""
    var aiTranslationTargetLanguage: String = "ar"
    var aiTranslationCustomEndpoint: String = "http://localhost:11434/v1/chat/completions"
    var aiTranslationModel: String = ""

    // Playback
    var resumePlaybackBehavior: String = "Ask"
    var nextEpisodeBehavior: String = "On · 10 s"
    var playAtOnce: Bool = false
    var playerEngineName: String = "AetherEngine"
    var audioOutputMode: String = "Dolby Digital Plus 5.1"
    var dolbyVisionEnabled: Bool = true
    var dolbyVisionP7ToHDR10Fallback: Bool = true
    var hdrEnabled: Bool = true
    var matchContentFrameRate: Bool = true
    var losslessMultichannelAudio: Bool = true
    var objectAudioEnabled: Bool = true
    var seekCacheEnabled: Bool = true
    var bufferAheadMode: String = "Standard"
    var rewindOnResumeSeconds: Int = 5
    var audioSyncOffsetMs: Int = 0
    var externalPlayer: String = "Built-in AetherEngine"

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
    var blurUnwatchedEpisodeThumbnails: Bool = false
    var hideUnwatchedEpisodeDescriptions: Bool = false
    var backgroundStyle: String = "Soft Glow"
    var autoPlayMutedTrailers: Bool = true
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
    var connectionTestStatus: String?
    var isTestingConnection: Bool = false

    // MARK: - Static Option Lists

    static let qualityOptions = ["4K", "1080p", "720p", "480p"]
    static let homeLayoutOptions = ["Ambient", "Spotlight"]
    static let moviesLayoutOptions = ["Grid", "List"]
    static let backgroundStyleOptions = AuraBackgroundStyle.allCases.map(\.rawValue)
    static let resumeOptions = ["Ask", "Resume", "Start Over"]
    static let nextEpisodeOptions = ["On · 10 s", "On · 5 s", "Off"]
    static let playerEngineOptions = ["AetherEngine", "AVPlayer"]
    static let audioModeOptions = ["Dolby Digital Plus 5.1", "Stereo"]
    static let bufferAheadOptions = ["Standard", "Extended", "Unlimited"]
    static let rewindOnResumeOptions = [0, 3, 5, 10]
    static let externalPlayerOptions = ["Built-in AetherEngine", "Infuse", "VidHub", "VLC", "SenPlayer"]
    static let subtitleAutoOptions = ["Preferred Languages", "Always On", "Off"]
    static let subtitleSizeOptions: [Double] = [34, 44, 54, 64]
    static let fontWeightOptions = ["Regular", "Medium", "Semibold", "Bold"]
    static let fontNameOptions = SubtitleProcessor.availableFonts
    static let subtitleColorOptions = SubtitleStyle.allColorNames
    static let subtitleBackgroundOpacityOptions: [Double] = [0.0, 0.25, 0.5, 0.75]
    static let subtitleBottomOffsetOptions: [Double] = [40, 56, 80, 110, 140]
    static let aiTranslationProviderOptions = [
        "OpenAI",
        "Gemini",
        "Claude",
        "Groq",
        "Custom (Ollama / OpenAI)"
    ]
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

    func defaultAIModelPlaceholder(for provider: String) -> String {
        switch provider {
        case "Gemini": return "gemini-2.0-flash (default)"
        case "Claude": return "claude-3-5-haiku-latest (default)"
        case "Groq": return "llama-3.3-70b-versatile (default)"
        case "Custom (Ollama / OpenAI)": return "llama3.2 (default)"
        default: return "gpt-4o-mini (default)"
        }
    }

    func displayLanguageName(for code: String) -> String {
        Self.languageOptions.first(where: { $0.code == code })?.name ?? code.uppercased()
    }

    func displayRewindOnResume(_ seconds: Int) -> String {
        seconds == 0 ? "Off" : "\(seconds) s"
    }

    func formatAudioSyncOffset(_ ms: Int) -> String {
        if ms == 0 { return "0 ms" }
        return ms > 0 ? "+\(ms) ms" : "\(ms) ms"
    }

    func adjustAudioSyncOffset(by deltaMs: Int) {
        audioSyncOffsetMs = max(-2000, min(2000, audioSyncOffsetMs + deltaMs))
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
                aioStreamsAdditionalUrls = settings.aioStreamsAdditionalUrls
                mdblistApiKey = settings.mdblistApiKey
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
                subtitleTextColor = Self.subtitleColorOptions.contains(settings.subtitleTextColor)
                    ? settings.subtitleTextColor
                    : "Light Gray"
                subtitleTextOpacity = settings.subtitleTextOpacity > 0.1 ? settings.subtitleTextOpacity : 0.80
                subtitleBackgroundOpacity = settings.subtitleBackgroundOpacity
                subtitleBottomOffset = settings.subtitleBottomOffset
                fixArabicRTL = settings.fixArabicRTL
                fixReversedPunctuation = settings.fixReversedPunctuation
                autoSyncSubtitles = settings.autoSyncSubtitles

                aiTranslationEnabled = settings.aiTranslationEnabled
                aiTranslationProvider = Self.aiTranslationProviderOptions.contains(settings.aiTranslationProvider)
                    ? settings.aiTranslationProvider
                    : "OpenAI"
                aiTranslationApiKey = settings.aiTranslationApiKey
                aiTranslationTargetLanguage = settings.aiTranslationTargetLanguage.isEmpty ? "ar" : settings.aiTranslationTargetLanguage
                aiTranslationCustomEndpoint = settings.aiTranslationCustomEndpoint.isEmpty
                    ? "http://localhost:11434/v1/chat/completions"
                    : settings.aiTranslationCustomEndpoint
                aiTranslationModel = settings.aiTranslationModel

                resumePlaybackBehavior = settings.resumePlaybackBehavior
                nextEpisodeBehavior = settings.nextEpisodeBehavior
                playAtOnce = settings.playAtOnce
                playerEngineName = Self.playerEngineOptions.contains(settings.playerEngineName) ? settings.playerEngineName : "AetherEngine"
                audioOutputMode = settings.audioOutputMode
                dolbyVisionEnabled = settings.dolbyVisionEnabled
                dolbyVisionP7ToHDR10Fallback = settings.dolbyVisionP7ToHDR10Fallback
                hdrEnabled = settings.hdrEnabled
                matchContentFrameRate = settings.matchContentFrameRate
                losslessMultichannelAudio = settings.losslessMultichannelAudio
                objectAudioEnabled = settings.objectAudioEnabled
                seekCacheEnabled = settings.seekCacheEnabled
                bufferAheadMode = Self.bufferAheadOptions.contains(settings.bufferAheadMode) ? settings.bufferAheadMode : "Standard"
                rewindOnResumeSeconds = Self.rewindOnResumeOptions.contains(settings.rewindOnResumeSeconds) ? settings.rewindOnResumeSeconds : 5
                audioSyncOffsetMs = max(-2000, min(2000, settings.audioSyncOffsetMs))
                externalPlayer = Self.externalPlayerOptions.contains(settings.externalPlayer) ? settings.externalPlayer : "Built-in AetherEngine"

                skipIntroMode = settings.skipIntroMode
                skipRecapMode = settings.skipRecapMode
                skipCreditsMode = settings.skipCreditsMode
                skipDelaySeconds = settings.skipDelaySeconds
                useIntroDB = settings.useIntroDB

                homeHeroStyle = settings.homeHeroStyle
                moviesLayoutStyle = settings.moviesLayoutStyle
                showWatchedIndicators = settings.showWatchedIndicators
                blurUnwatchedEpisodeThumbnails = settings.blurUnwatchedEpisodeThumbnails
                hideUnwatchedEpisodeDescriptions = settings.hideUnwatchedEpisodeDescriptions
                backgroundStyle = Self.backgroundStyleOptions.contains(settings.backgroundStyle) ? settings.backgroundStyle : "Soft Glow"
                autoPlayMutedTrailers = settings.autoPlayMutedTrailers
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

            settings.tmdbApiKey = tmdbApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.aioStreamsUrl = aioStreamsUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.aioStreamsAdditionalUrls = Self.splitManifestEntries(aioStreamsAdditionalUrls).joined(separator: "\n")
            settings.mdblistApiKey = mdblistApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
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
            settings.subtitleTextColor = subtitleTextColor
            settings.subtitleTextOpacity = min(max(subtitleTextOpacity, 0.40), 1.0)
            settings.subtitleBackgroundOpacity = subtitleBackgroundOpacity
            settings.subtitleBottomOffset = subtitleBottomOffset
            settings.fixArabicRTL = fixArabicRTL
            settings.fixReversedPunctuation = fixReversedPunctuation
            settings.autoSyncSubtitles = autoSyncSubtitles

            settings.aiTranslationEnabled = aiTranslationEnabled
            settings.aiTranslationProvider = aiTranslationProvider
            settings.aiTranslationApiKey = aiTranslationApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.aiTranslationTargetLanguage = aiTranslationTargetLanguage
            settings.aiTranslationCustomEndpoint = aiTranslationCustomEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.aiTranslationModel = aiTranslationModel.trimmingCharacters(in: .whitespacesAndNewlines)

            settings.resumePlaybackBehavior = resumePlaybackBehavior
            settings.nextEpisodeBehavior = nextEpisodeBehavior
            settings.playAtOnce = playAtOnce
            settings.playerEngineName = playerEngineName
            settings.audioOutputMode = audioOutputMode
            settings.dolbyVisionEnabled = dolbyVisionEnabled
            settings.dolbyVisionP7ToHDR10Fallback = dolbyVisionP7ToHDR10Fallback
            settings.hdrEnabled = hdrEnabled
            settings.matchContentFrameRate = matchContentFrameRate
            settings.losslessMultichannelAudio = losslessMultichannelAudio
            settings.objectAudioEnabled = objectAudioEnabled
            settings.seekCacheEnabled = seekCacheEnabled
            settings.bufferAheadMode = bufferAheadMode
            settings.rewindOnResumeSeconds = rewindOnResumeSeconds
            settings.audioSyncOffsetMs = audioSyncOffsetMs
            settings.externalPlayer = externalPlayer

            settings.skipIntroMode = skipIntroMode
            settings.skipRecapMode = skipRecapMode
            settings.skipCreditsMode = skipCreditsMode
            settings.skipDelaySeconds = skipDelaySeconds
            settings.useIntroDB = useIntroDB

            settings.homeHeroStyle = homeHeroStyle
            settings.moviesLayoutStyle = moviesLayoutStyle
            settings.showWatchedIndicators = showWatchedIndicators
            settings.blurUnwatchedEpisodeThumbnails = blurUnwatchedEpisodeThumbnails
            settings.hideUnwatchedEpisodeDescriptions = hideUnwatchedEpisodeDescriptions
            settings.backgroundStyle = backgroundStyle
            settings.autoPlayMutedTrailers = autoPlayMutedTrailers
            settings.includeLogosInHome = includeLogosInHome
            settings.preferredArtworkLanguage = preferredArtworkLanguage

            settings.traktUsername = traktUsername
            settings.traktScrobbleEnabled = traktScrobbleEnabled

            try context.save()

            TMDBService.shared.apiKey = tmdbApiKey.isEmpty ? "d767cb12181edaa01840442c704329be" : tmdbApiKey
            AIOStreamsService.shared.manifestURL = aioStreamsUrl
            AIOStreamsService.shared.additionalManifestURLs = aioStreamsAdditionalUrls
            MDBListService.shared.apiKey = mdblistApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
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

    @MainActor
    func clearCustomArtwork(context: ModelContext) {
        let descriptor = FetchDescriptor<CustomArtwork>()
        do {
            let items = try context.fetch(descriptor)
            for item in items { context.delete(item) }
            try context.save()
            statusMessage = "Restored default TMDB artwork for \(items.count) titles."
        } catch {
            self.error = error.localizedDescription
        }
    }

    var configuredManifestURLs: [String] {
        Self.splitManifestEntries("\(aioStreamsUrl)\n\(aioStreamsAdditionalUrls)")
    }

    private static func cleanedManifestEntry(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return AIOStreamsService.normalizedManifestURL(from: trimmed)
    }

    private static func splitManifestEntries(_ raw: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let parts = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    @MainActor
    func addAndValidateManifestURL(_ rawInput: String, context: ModelContext) async {
        let candidates = Self.splitManifestEntries(rawInput)
        guard !candidates.isEmpty else {
            connectionTestStatus = "Paste a Stremio, AIOStreams, or Nuvio manifest.json URL first."
            return
        }

        isTestingConnection = true
        connectionTestStatus = nil
        defer { isTestingConnection = false }

        var validatedNames: [String] = []
        var merged = configuredManifestURLs

        for rawCandidate in candidates {
            do {
                let (normalized, manifest) = try await AIOStreamsService.shared.validateManifest(at: rawCandidate)
                if !merged.contains(normalized) {
                    merged.append(normalized)
                }
                let addonTitle = manifest.name ?? URL(string: normalized)?.host ?? "Addon"
                let addonVer = manifest.version.map { " v\($0)" } ?? ""
                validatedNames.append("\(addonTitle)\(addonVer)")
            } catch {
                connectionTestStatus = "Validation failed: \(error.localizedDescription)"
                return
            }
        }

        aioStreamsUrl = merged.first ?? ""
        aioStreamsAdditionalUrls = merged.dropFirst().joined(separator: "\n")
        quickManifestInput = ""
        saveSettings(context: context)

        let summary = validatedNames.joined(separator: ", ")
        connectionTestStatus = "Connected & Saved: \(summary) (\(merged.count) active)"
        statusMessage = "Saved \(summary)."
    }

    @MainActor
    func removeManifestURL(_ targetURL: String, context: ModelContext) {
        let remaining = configuredManifestURLs.filter { $0 != targetURL }
        aioStreamsUrl = remaining.first ?? ""
        aioStreamsAdditionalUrls = remaining.dropFirst().joined(separator: "\n")
        saveSettings(context: context)
        connectionTestStatus = remaining.isEmpty
            ? "Removed manifest URL."
            : "Removed manifest. \(remaining.count) addon(s) remaining."
    }

    @MainActor
    func makePrimaryManifestURL(_ targetURL: String, context: ModelContext) {
        let others = configuredManifestURLs.filter { $0 != targetURL }
        aioStreamsUrl = targetURL
        aioStreamsAdditionalUrls = others.joined(separator: "\n")
        saveSettings(context: context)
        connectionTestStatus = "Set primary manifest: \(targetURL)"
    }

    @MainActor
    func testAIOStreamsConnection() async {
        isTestingConnection = true
        connectionTestStatus = nil
        AIOStreamsService.shared.manifestURL = aioStreamsUrl
        AIOStreamsService.shared.additionalManifestURLs = aioStreamsAdditionalUrls

        let urls = AIOStreamsService.shared.allManifestURLs
        guard let primary = urls.first else {
            connectionTestStatus = AIOStreamsError.missingManifestURL.localizedDescription
            isTestingConnection = false
            return
        }

        do {
            let (_, manifest) = try await AIOStreamsService.shared.validateManifest(at: primary)
            let addonName = manifest.name ?? "AIOStreams"
            let addonVersion = manifest.version ?? "1.0"
            let extraCount = max(urls.count - 1, 0)
            let extraSuffix = extraCount > 0 ? " + \(extraCount) extra addon(s)" : ""
            connectionTestStatus = "Connected to \(addonName) (v\(addonVersion))\(extraSuffix)"
        } catch {
            connectionTestStatus = error.localizedDescription
        }

        isTestingConnection = false
    }
}
