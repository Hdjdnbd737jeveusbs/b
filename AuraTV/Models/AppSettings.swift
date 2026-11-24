import Foundation
import SwiftData

@Model
class AppSettings {
    @Attribute(.unique) var id: String = "default"
    var tmdbApiKey: String = ""
    var aioStreamsUrl: String = ""
    var preferredQuality: String = "4K"
    var preferredLanguage: String = "en"
    var subtitleLanguage: String = "ar"

    // MARK: - Phase 3: Subtitles & Arabic Settings
    var subdlApiKey: String = ""
    var openSubtitlesApiKey: String = ""
    var subtitleFontSize: Double = 44.0
    var subtitleFontWeight: String = "Bold"
    var subtitleFontName: String = "System"
    var subtitleTextColor: String = "White"
    var subtitleBackgroundOpacity: Double = 0.35
    var subtitleBottomOffset: Double = 60.0
    var fixArabicRTL: Bool = true
    var fixReversedPunctuation: Bool = true
    var autoSyncSubtitles: Bool = false

    // MARK: - Convenience Init

    convenience init(
        id: String = "default",
        tmdbApiKey: String = "",
        aioStreamsUrl: String = "",
        preferredQuality: String = "4K",
        preferredLanguage: String = "en",
        subtitleLanguage: String = "ar",
        subdlApiKey: String = "",
        openSubtitlesApiKey: String = "",
        subtitleFontSize: Double = 44.0,
        subtitleFontWeight: String = "Bold",
        subtitleFontName: String = "System",
        subtitleTextColor: String = "White",
        subtitleBackgroundOpacity: Double = 0.35,
        subtitleBottomOffset: Double = 60.0,
        fixArabicRTL: Bool = true,
        fixReversedPunctuation: Bool = true,
        autoSyncSubtitles: Bool = false
    ) {
        self.init()
        self.id = id
        self.tmdbApiKey = tmdbApiKey
        self.aioStreamsUrl = aioStreamsUrl
        self.preferredQuality = preferredQuality
        self.preferredLanguage = preferredLanguage
        self.subtitleLanguage = subtitleLanguage
        self.subdlApiKey = subdlApiKey
        self.openSubtitlesApiKey = openSubtitlesApiKey
        self.subtitleFontSize = subtitleFontSize
        self.subtitleFontWeight = subtitleFontWeight
        self.subtitleFontName = subtitleFontName
        self.subtitleTextColor = subtitleTextColor
        self.subtitleBackgroundOpacity = subtitleBackgroundOpacity
        self.subtitleBottomOffset = subtitleBottomOffset
        self.fixArabicRTL = fixArabicRTL
        self.fixReversedPunctuation = fixReversedPunctuation
        self.autoSyncSubtitles = autoSyncSubtitles
    }
}
