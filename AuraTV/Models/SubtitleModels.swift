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

struct SubtitleColorPreset: Identifiable, Hashable {
    let name: String
    let subtitle: String
    let color: Color
    var id: String { name }
}

struct SubtitleStyle: Codable, Hashable {
    var fontSize: Double = 58.0
    var fontWeight: String = "Medium"
    var fontName: String = "The Year of The Camel"
    var textColor: String = "Light Gray"
    var textOpacity: Double = 0.80
    var backgroundOpacity: Double = 0.0
    var bottomOffset: Double = 56.0

    static let defaultStyle = SubtitleStyle()

    static let miniLEDPresets: [SubtitleColorPreset] = [
        SubtitleColorPreset(
            name: "Light Gray",
            subtitle: "#BFBFBF · Recommended",
            color: Color(red: 191 / 255, green: 191 / 255, blue: 191 / 255)
        ),
        SubtitleColorPreset(
            name: "Soft Gray",
            subtitle: "#CCCCCC · Low Bloom",
            color: Color(red: 204 / 255, green: 204 / 255, blue: 204 / 255)
        ),
        SubtitleColorPreset(
            name: "Warm Off-White",
            subtitle: "#D6D1C4 · Paper Warm",
            color: Color(red: 214 / 255, green: 209 / 255, blue: 196 / 255)
        ),
        SubtitleColorPreset(
            name: "Soft Cinema Yellow",
            subtitle: "#E5C76B · Classic Cinema",
            color: Color(red: 229 / 255, green: 199 / 255, blue: 107 / 255)
        )
    ]

    static let allColorNames: [String] = miniLEDPresets.map(\.name) + ["White"]

    enum CodingKeys: String, CodingKey {
        case fontSize
        case fontWeight
        case fontName
        case textColor
        case textOpacity
        case backgroundOpacity
        case bottomOffset
    }

    init(
        fontSize: Double = 44.0,
        fontWeight: String = "Bold",
        fontName: String = "System",
        textColor: String = "Light Gray",
        textOpacity: Double = 0.80,
        backgroundOpacity: Double = 0.0,
        bottomOffset: Double = 56.0
    ) {
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.fontName = fontName
        self.textColor = textColor
        self.textOpacity = textOpacity
        self.backgroundOpacity = backgroundOpacity
        self.bottomOffset = bottomOffset
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 44.0
        self.fontWeight = try c.decodeIfPresent(String.self, forKey: .fontWeight) ?? "Bold"
        self.fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? "System"
        self.textColor = try c.decodeIfPresent(String.self, forKey: .textColor) ?? "Light Gray"
        self.textOpacity = try c.decodeIfPresent(Double.self, forKey: .textOpacity) ?? 0.80
        self.backgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 0.0
        self.bottomOffset = try c.decodeIfPresent(Double.self, forKey: .bottomOffset) ?? 56.0
    }

    var baseColor: Color {
        switch textColor.lowercased() {
        case "light gray", "light gray (#bfbfbf)":
            return Color(red: 191 / 255, green: 191 / 255, blue: 191 / 255)
        case "soft gray", "soft gray (#cccccc)":
            return Color(red: 204 / 255, green: 204 / 255, blue: 204 / 255)
        case "warm off-white", "warm off-white (#d6d1c4)":
            return Color(red: 214 / 255, green: 209 / 255, blue: 196 / 255)
        case "soft cinema yellow", "soft cinema yellow (#e5c76b)", "yellow":
            return Color(red: 229 / 255, green: 199 / 255, blue: 107 / 255)
        case "green":
            return .green
        case "cyan":
            return Color(red: 0.2, green: 0.85, blue: 1.0)
        case "white":
            return .white
        default:
            return Color(red: 191 / 255, green: 191 / 255, blue: 191 / 255)
        }
    }

    var colorValue: Color {
        baseColor.opacity(min(max(textOpacity, 0.35), 1.0))
    }

    var font: Font {
        ImportedSubtitleFonts.restore()
        let weight: Font.Weight = {
            switch fontWeight.lowercased() {
            case "regular": return .regular
            case "medium": return .medium
            case "semibold": return .semibold
            case "heavy": return .heavy
            default: return .bold
            }
        }()

        if fontName == "The Year of The Camel" {
            return .custom("TheYearofTheCamel-Medium", fixedSize: fontSize)
        }
        if fontName == "System" || fontName.isEmpty {
            return .system(size: fontSize, weight: weight)
        } else if fontName == "IBM Plex Sans Arabic" {
            let psName: String
            switch fontWeight.lowercased() {
            case "regular": psName = "IBMPlexSansArabic-Regular"
            case "medium": psName = "IBMPlexSansArabic-Medium"
            default: psName = "IBMPlexSansArabic-Bold"
            }
            return .custom(psName, size: fontSize)
        } else if fontName == "Tajawal" {
            let psName: String
            switch fontWeight.lowercased() {
            case "regular": psName = "Tajawal-Regular"
            case "medium": psName = "Tajawal-Medium"
            default: psName = "Tajawal-Bold"
            }
            return .custom(psName, size: fontSize)
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
