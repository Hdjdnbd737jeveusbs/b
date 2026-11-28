import Foundation
import SwiftData

@Model
class AppSettings {
    @Attribute(.unique) var id: String = "default"
    var tmdbApiKey: String = "d767cb12181edaa01840442c704329be"
    var aioStreamsUrl: String = ""
    var aioStreamsAdditionalUrls: String = ""
    var mdblistApiKey: String = ""
    var preferredQuality: String = "4K"
    var preferredLanguage: String = "en"
    var subtitleLanguage: String = "ar"

    // MARK: - Subtitles & Arabic Settings
    var subdlApiKey: String = ""
    var openSubtitlesApiKey: String = ""
    var subtitleFontSize: Double = 58.0
    var subtitleFontWeight: String = "Medium"
    var subtitleFontName: String = "The Year of The Camel"
    var subtitleTextColor: String = "Light Gray"
    var subtitleTextOpacity: Double = 0.80
    var subtitleBackgroundOpacity: Double = 0.0
    var subtitleBottomOffset: Double = 56.0
    var fixArabicRTL: Bool = true
    var fixReversedPunctuation: Bool = true
    var autoSyncSubtitles: Bool = false
    var subtitleAutoMode: String = "Preferred Languages"
    var secondarySubtitleLanguage: String = "en"

    // MARK: - AI Live Subtitle Translation
    var aiTranslationEnabled: Bool = false
    var aiTranslationProvider: String = "OpenAI"
    var aiTranslationApiKey: String = ""
    var aiTranslationTargetLanguage: String = "ar"
    var aiTranslationCustomEndpoint: String = "http://localhost:11434/v1/chat/completions"
    var aiTranslationModel: String = ""

    // MARK: - Playback Settings
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

    // MARK: - Skip Intro & Credits
    var skipIntroMode: String = "Skip After Delay"
    var skipRecapMode: String = "Skip After Delay"
    var skipCreditsMode: String = "Show Button"
    var skipDelaySeconds: Int = 8
    var useIntroDB: Bool = true

    // MARK: - Appearance & Artwork
    var homeHeroStyle: String = "Ambient"
    var moviesLayoutStyle: String = "Grid"
    var showWatchedIndicators: Bool = true
    var blurUnwatchedEpisodeThumbnails: Bool = false
    var hideUnwatchedEpisodeDescriptions: Bool = false
    var backgroundStyle: String = "Soft Glow"
    var autoPlayMutedTrailers: Bool = true
    var includeLogosInHome: Bool = true
    var preferredArtworkLanguage: String = "English"

    // MARK: - Trakt
    var traktUsername: String = ""
    var traktScrobbleEnabled: Bool = true

    // MARK: - Init

    init(
        id: String = "default",
        tmdbApiKey: String = "d767cb12181edaa01840442c704329be",
        aioStreamsUrl: String = "",
        aioStreamsAdditionalUrls: String = "",
        mdblistApiKey: String = "",
        preferredQuality: String = "4K",
        preferredLanguage: String = "en",
        subtitleLanguage: String = "ar",
        subdlApiKey: String = "",
        openSubtitlesApiKey: String = "",
        subtitleFontSize: Double = 58.0,
        subtitleFontWeight: String = "Medium",
        subtitleFontName: String = "The Year of The Camel",
        subtitleTextColor: String = "Light Gray",
        subtitleTextOpacity: Double = 0.80,
        subtitleBackgroundOpacity: Double = 0.0,
        subtitleBottomOffset: Double = 56.0,
        fixArabicRTL: Bool = true,
        fixReversedPunctuation: Bool = true,
        autoSyncSubtitles: Bool = false,
        subtitleAutoMode: String = "Preferred Languages",
        secondarySubtitleLanguage: String = "en",
        aiTranslationEnabled: Bool = false,
        aiTranslationProvider: String = "OpenAI",
        aiTranslationApiKey: String = "",
        aiTranslationTargetLanguage: String = "ar",
        aiTranslationCustomEndpoint: String = "http://localhost:11434/v1/chat/completions",
        aiTranslationModel: String = "",
        resumePlaybackBehavior: String = "Ask",
        nextEpisodeBehavior: String = "On · 10 s",
        playAtOnce: Bool = false,
        playerEngineName: String = "AetherEngine",
        audioOutputMode: String = "Dolby Digital Plus 5.1",
        dolbyVisionEnabled: Bool = true,
        dolbyVisionP7ToHDR10Fallback: Bool = true,
        hdrEnabled: Bool = true,
        matchContentFrameRate: Bool = true,
        losslessMultichannelAudio: Bool = true,
        objectAudioEnabled: Bool = true,
        seekCacheEnabled: Bool = true,
        bufferAheadMode: String = "Standard",
        rewindOnResumeSeconds: Int = 5,
        audioSyncOffsetMs: Int = 0,
        externalPlayer: String = "Built-in AetherEngine",
        skipIntroMode: String = "Skip After Delay",
        skipRecapMode: String = "Skip After Delay",
        skipCreditsMode: String = "Show Button",
        skipDelaySeconds: Int = 8,
        useIntroDB: Bool = true,
        homeHeroStyle: String = "Ambient",
        moviesLayoutStyle: String = "Grid",
        showWatchedIndicators: Bool = true,
        blurUnwatchedEpisodeThumbnails: Bool = false,
        hideUnwatchedEpisodeDescriptions: Bool = false,
        backgroundStyle: String = "Soft Glow",
        autoPlayMutedTrailers: Bool = true,
        includeLogosInHome: Bool = true,
        preferredArtworkLanguage: String = "English",
        traktUsername: String = "",
        traktScrobbleEnabled: Bool = true
    ) {
        self.id = id
        self.tmdbApiKey = tmdbApiKey
        self.aioStreamsUrl = aioStreamsUrl
        self.aioStreamsAdditionalUrls = aioStreamsAdditionalUrls
        self.mdblistApiKey = mdblistApiKey
        self.preferredQuality = preferredQuality
        self.preferredLanguage = preferredLanguage
        self.subtitleLanguage = subtitleLanguage
        self.subdlApiKey = subdlApiKey
        self.openSubtitlesApiKey = openSubtitlesApiKey
        self.subtitleFontSize = subtitleFontSize
        self.subtitleFontWeight = subtitleFontWeight
        self.subtitleFontName = subtitleFontName
        self.subtitleTextColor = subtitleTextColor
        self.subtitleTextOpacity = subtitleTextOpacity
        self.subtitleBackgroundOpacity = subtitleBackgroundOpacity
        self.subtitleBottomOffset = subtitleBottomOffset
        self.fixArabicRTL = fixArabicRTL
        self.fixReversedPunctuation = fixReversedPunctuation
        self.autoSyncSubtitles = autoSyncSubtitles
        self.subtitleAutoMode = subtitleAutoMode
        self.secondarySubtitleLanguage = secondarySubtitleLanguage
        self.aiTranslationEnabled = aiTranslationEnabled
        self.aiTranslationProvider = aiTranslationProvider
        self.aiTranslationApiKey = aiTranslationApiKey
        self.aiTranslationTargetLanguage = aiTranslationTargetLanguage
        self.aiTranslationCustomEndpoint = aiTranslationCustomEndpoint
        self.aiTranslationModel = aiTranslationModel
        self.resumePlaybackBehavior = resumePlaybackBehavior
        self.nextEpisodeBehavior = nextEpisodeBehavior
        self.playAtOnce = playAtOnce
        self.playerEngineName = playerEngineName
        self.audioOutputMode = audioOutputMode
        self.dolbyVisionEnabled = dolbyVisionEnabled
        self.dolbyVisionP7ToHDR10Fallback = dolbyVisionP7ToHDR10Fallback
        self.hdrEnabled = hdrEnabled
        self.matchContentFrameRate = matchContentFrameRate
        self.losslessMultichannelAudio = losslessMultichannelAudio
        self.objectAudioEnabled = objectAudioEnabled
        self.seekCacheEnabled = seekCacheEnabled
        self.bufferAheadMode = bufferAheadMode
        self.rewindOnResumeSeconds = rewindOnResumeSeconds
        self.audioSyncOffsetMs = audioSyncOffsetMs
        self.externalPlayer = externalPlayer
        self.skipIntroMode = skipIntroMode
        self.skipRecapMode = skipRecapMode
        self.skipCreditsMode = skipCreditsMode
        self.skipDelaySeconds = skipDelaySeconds
        self.useIntroDB = useIntroDB
        self.homeHeroStyle = homeHeroStyle
        self.moviesLayoutStyle = moviesLayoutStyle
        self.showWatchedIndicators = showWatchedIndicators
        self.blurUnwatchedEpisodeThumbnails = blurUnwatchedEpisodeThumbnails
        self.hideUnwatchedEpisodeDescriptions = hideUnwatchedEpisodeDescriptions
        self.backgroundStyle = backgroundStyle
        self.autoPlayMutedTrailers = autoPlayMutedTrailers
        self.includeLogosInHome = includeLogosInHome
        self.preferredArtworkLanguage = preferredArtworkLanguage
        self.traktUsername = traktUsername
        self.traktScrobbleEnabled = traktScrobbleEnabled
    }
}
