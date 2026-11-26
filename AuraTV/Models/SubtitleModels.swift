import Foundation
import SwiftUI

// MARK: - Subtitle Source

enum SubtitleSource: String, Codable, CaseIterable {
    case embedded = "Embedded"
    case subdl = "SubDL"
    case openSubtitles = "OpenSubtitles"
    case wyzie = "Wyzie"

    var badgeName: String {
        switch self {
        case .embedded: return "Stream"
        case .subdl: return "SubDL"
        case .openSubtitles: return "OpenSub"
        case .wyzie: return "Wyzie"
        }
    }
}

// MARK: - Subtitle Track Item

struct SubtitleTrackItem: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let languageCode: String // "ar", "en", etc.
    let source: SubtitleSource
    let downloadURL: URL?
    let releaseInfo: String?
    let hearingImpaired: Bool
    let isEmbedded: Bool
    let embeddedTrackId: Int?
    let openSubtitlesFileId: Int?

    init(
        id: String,
        name: String,
        language: String,
        languageCode: String,
        source: SubtitleSource,
        downloadURL: URL?,
        releaseInfo: String?,
        hearingImpaired: Bool,
        isEmbedded: Bool,
        embeddedTrackId: Int?,
        openSubtitlesFileId: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.languageCode = languageCode
        self.source = source
        self.downloadURL = downloadURL
        self.releaseInfo = releaseInfo
        self.hearingImpaired = hearingImpaired
        self.isEmbedded = isEmbedded
        self.embeddedTrackId = embeddedTrackId
        self.openSubtitlesFileId = openSubtitlesFileId
    }

    var displayName: String {
        var parts: [String] = []
        parts.append(language)
        if let rel = releaseInfo, !rel.isEmpty {
            parts.append(rel)
        } else if !name.isEmpty && name != language {
            parts.append(name)
        }
        parts.append("[\(source.badgeName)]")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Subtitle Cue

struct AuraSubtitleCue: Identifiable, Hashable {
    let id: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
    var text: String
    var processedText: String?
    var isArabic: Bool

    /// Check if this cue should be displayed at playback time `time` (with optional sync offset)
    func isActive(at time: TimeInterval, offset: TimeInterval = 0) -> Bool {
        let adjustedTime = time - offset
        return adjustedTime >= startTime && adjustedTime <= endTime
    }
}

// MARK: - Subtitle Style Configuration

struct SubtitleStyle: Codable, Hashable {
    var fontSize: Double = 44.0
    var fontWeight: String = "Bold"
    var fontName: String = "System"
    var textColor: String = "White"
    var backgroundOpacity: Double = 0.0
    var bottomOffset: Double = 56.0

    static let defaultStyle = SubtitleStyle()

    var colorValue: Color {
        switch textColor.lowercased() {
        case "yellow": return .yellow
        case "green": return .green
        case "cyan": return Color(red: 0.2, green: 0.85, blue: 1.0)
        default: return .white
        }
    }

    var font: Font {
        let weight: Font.Weight = {
            switch fontWeight.lowercased() {
            case "regular": return .regular
            case "medium": return .medium
            case "semibold": return .semibold
            case "heavy": return .heavy
            default: return .bold
            }
        }()

        if fontName == "System" || fontName.isEmpty {
            return .system(size: fontSize, weight: weight)
        } else {
            return .custom(fontName, size: fontSize)
        }
    }
}

// MARK: - Subtitle Sync Settings

struct SubtitleSyncSettings: Codable, Hashable {
    var manualOffset: Double = 0.0
    var autoSyncEnabled: Bool = false
    var fixRTL: Bool = true
    var fixReversedPunctuation: Bool = true

    static let defaultSettings = SubtitleSyncSettings()
}

// MARK: - SubDL API Response Models

struct SubDLResponse: Codable {
    let status: Bool?
    let results: [SubDLItem]?
    let subtitles: [SubDLSubtitle]?
}

struct SubDLItem: Codable {
    let sdId: Int?
    let type: String?
    let name: String?
    let imdbId: String?
    let tmdbId: Int?
    let year: Int?
    let subtitles: [SubDLSubtitle]?
}

struct SubDLSubtitle: Codable {
    let releaseName: String?
    let name: String?
    let lang: String?
    let author: String?
    let url: String?
    let hi: Bool?
}

// MARK: - OpenSubtitles API Response Models

struct OpenSubtitlesResponse: Codable {
    let totalPages: Int?
    let totalCount: Int?
    let data: [OpenSubtitlesData]?
}

struct OpenSubtitlesData: Codable {
    let id: String?
    let attributes: OpenSubtitlesAttributes?
}

struct OpenSubtitlesAttributes: Codable {
    let subtitleId: String?
    let language: String?
    let release: String?
    let hearingImpaired: Bool?
    let votes: Int?
    let ratings: Double?
    let files: [OpenSubtitlesFile]?
}

struct OpenSubtitlesFile: Codable {
    let fileId: Int?
    let cdNumber: Int?
    let fileName: String?
}

struct OpenSubtitlesDownloadResponse: Codable {
    let link: String?
    let fileName: String?
    let requests: Int?
    let remaining: Int?
    let message: String?
}

// MARK: - Wyzie API Response Models

struct WyzieSubtitleItem: Codable {
    let id: String?
    let language: String?
    let title: String?
    let url: String?
    let format: String?
}
