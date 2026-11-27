import Foundation

// MARK: - Stremio Manifest

struct StremioManifest: Codable {
    let id: String?
    let name: String?
    let description: String?
    let version: String?
    let catalogs: [StremioCatalog]?
    let resources: [StremioResource]?
    let types: [String]?
}

struct StremioCatalog: Codable {
    let type: String?
    let id: String?
    let name: String?
}

struct StremioResource: Codable {
    let name: String?
    let types: [String]?
    let idPrefixes: [String]?

    enum CodingKeys: String, CodingKey {
        case name
        case types
        case idPrefixes
    }

    init(name: String? = nil, types: [String]? = nil, idPrefixes: [String]? = nil) {
        self.name = name
        self.types = types
        self.idPrefixes = idPrefixes
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let rawName = try? single.decode(String.self) {
            self.name = rawName
            self.types = nil
            self.idPrefixes = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.types = try container.decodeIfPresent([String].self, forKey: .types)
        self.idPrefixes = try container.decodeIfPresent([String].self, forKey: .idPrefixes)
    }
}

// MARK: - Stremio Stream Response

struct StremioStreamResponse: Codable {
    let streams: [StremioStream]?
}

struct StremioStream: Codable, Identifiable, Hashable, Sendable {
    let name: String?
    let title: String?
    let description: String?
    let url: String?
    let infoHash: String?
    let fileIdx: Int?
    let behaviorHints: StreamBehaviorHints?
    private let cachedParsedInfo: ParsedStreamInfo?

    enum CodingKeys: String, CodingKey {
        case name, title, description, url, infoHash, fileIdx, behaviorHints
    }

    init(
        name: String? = nil,
        title: String? = nil,
        description: String? = nil,
        url: String? = nil,
        infoHash: String? = nil,
        fileIdx: Int? = nil,
        behaviorHints: StreamBehaviorHints? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.url = url
        self.infoHash = infoHash
        self.fileIdx = fileIdx
        self.behaviorHints = behaviorHints
        self.cachedParsedInfo = ParsedStreamInfo(name: name, title: title, description: description, behaviorHints: behaviorHints)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let n = try c.decodeIfPresent(String.self, forKey: .name)
        let t = try c.decodeIfPresent(String.self, forKey: .title)
        let d = try c.decodeIfPresent(String.self, forKey: .description)
        let u = try c.decodeIfPresent(String.self, forKey: .url)
        let ih = try c.decodeIfPresent(String.self, forKey: .infoHash)
        let fi = try c.decodeIfPresent(Int.self, forKey: .fileIdx)
        let bh = try c.decodeIfPresent(StreamBehaviorHints.self, forKey: .behaviorHints)
        self.init(name: n, title: t, description: d, url: u, infoHash: ih, fileIdx: fi, behaviorHints: bh)
    }

    var id: String {
        url ?? infoHash ?? "\(name ?? "")_\(title ?? "")_\(description ?? "")"
    }

    /// Clean combined description/title text shown in stream rows
    var displayDetails: String {
        [title, description]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    /// Returns cached stream metadata (precomputed off MainActor during JSON decoding)
    var parsedInfo: ParsedStreamInfo {
        cachedParsedInfo ?? ParsedStreamInfo(name: name, title: title, description: description, behaviorHints: behaviorHints)
    }
}

struct StreamBehaviorHints: Codable, Hashable, Sendable {
    let bingeGroup: String?
    let filename: String?
    let videoSize: Int?

    /// Video size formatted as human-readable string
    var formattedSize: String? {
        guard let size = videoSize, size > 0 else { return nil }
        let gb = Double(size) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(size) / 1_048_576.0
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Parsed Stream Info

struct ParsedStreamInfo: Hashable, Sendable {
    let resolution: StreamResolution
    let hdrType: StreamHDR?
    let releaseType: String?
    let audioCodec: String?
    let fileSize: String?
    let isCached: Bool
    let providerName: String?
    let qualitySortOrder: Int

    init(name: String?, title: String?, description: String? = nil, behaviorHints: StreamBehaviorHints? = nil) {
        let combinedOriginal = [name, title, description, behaviorHints?.filename]
            .compactMap { $0 }
            .joined(separator: " ")
        let combined = combinedOriginal.uppercased()

        // Resolution
        if combined.contains("2160") || combined.contains("4K") || combined.contains("UHD") {
            self.resolution = .uhd4k
            self.qualitySortOrder = 0
        } else if combined.contains("1080") {
            self.resolution = .fhd1080p
            self.qualitySortOrder = 1
        } else if combined.contains("720") {
            self.resolution = .hd720p
            self.qualitySortOrder = 2
        } else if combined.contains("480") {
            self.resolution = .sd480p
            self.qualitySortOrder = 3
        } else {
            self.resolution = .unknown
            self.qualitySortOrder = 4
        }

        // Source / Release Type (REMUX, BluRay, WEB-DL)
        if combined.contains("REMUX") {
            self.releaseType = "REMUX"
        } else if combined.contains("BLURAY") || combined.contains("BLU-RAY") || combined.contains("BDRIP") {
            self.releaseType = "BluRay"
        } else if combined.contains("WEB-DL") || combined.contains("WEBDL") {
            self.releaseType = "WEB-DL"
        } else if combined.contains("WEBRIP") {
            self.releaseType = "WEBRip"
        } else {
            self.releaseType = nil
        }

        // HDR
        if combined.contains("DOLBY VISION") || combined.contains("DOVI") || combined.contains("DV") || combined.contains("DOLBYVISION") {
            self.hdrType = .dolbyVision
        } else if combined.contains("HDR10+") || combined.contains("HDR10PLUS") {
            self.hdrType = .hdr10Plus
        } else if combined.contains("HDR10") || combined.contains("HDR") {
            self.hdrType = .hdr10
        } else {
            self.hdrType = nil
        }

        // Audio
        if combined.contains("ATMOS") {
            self.audioCodec = "Atmos"
        } else if combined.contains("TRUEHD") || combined.contains("TRUE HD") {
            self.audioCodec = "TrueHD"
        } else if combined.contains("DTS-HD") || combined.contains("DTS HD") {
            self.audioCodec = "DTS-HD"
        } else if combined.contains("DTS") {
            self.audioCodec = "DTS"
        } else if combined.contains("DD+") || combined.contains("EAC3") || combined.contains("DDP") || combined.contains("DDPLUS") {
            self.audioCodec = "DD+"
        } else if combined.contains("DD5.1") || combined.contains("AC3") || combined.contains("5.1") {
            self.audioCodec = "5.1"
        } else if combined.contains("AAC") {
            self.audioCodec = "AAC"
        } else {
            self.audioCodec = nil
        }

        // File size
        let sizePattern = try? NSRegularExpression(pattern: #"(\d+\.?\d*)\s*(TB|GB|MB)"#, options: .caseInsensitive)
        if let match = sizePattern?.firstMatch(
            in: combinedOriginal,
            range: NSRange(combinedOriginal.startIndex..., in: combinedOriginal)
        ),
           let nr = Range(match.range(at: 1), in: combinedOriginal),
           let ur = Range(match.range(at: 2), in: combinedOriginal) {
            self.fileSize = "\(combinedOriginal[nr]) \(combinedOriginal[ur].uppercased())"
        } else {
            self.fileSize = behaviorHints?.formattedSize
        }

        // Cached (debrid)
        self.isCached = combined.contains("⚡")
            || combined.contains("CACHED")
            || combined.contains("[RD+]")
            || combined.contains("[AD+]")
            || combined.contains("[PM+]")
            || combined.contains("[TB+]")
            || combined.contains("[RD")
            || combined.contains("[AD")
            || combined.contains("[PM")
            || combined.contains("[DL")

        // Provider name (first line of `name`)
        self.providerName = name?
            .components(separatedBy: "\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Compact technical badges list for Player HUD top bar
    var techBadges: [String] {
        var list: [String] = []
        if resolution != .unknown { list.append(resolution.displayName) }
        if let hdrType { list.append(hdrType.displayName) }
        if let releaseType { list.append(releaseType) }
        if let audioCodec { list.append(audioCodec) }
        return list
    }
}

// MARK: - Enums

enum StreamResolution: String, Hashable, CaseIterable, Sendable {
    case uhd4k = "4K"
    case fhd1080p = "1080p"
    case hd720p = "720p"
    case sd480p = "480p"
    case unknown = "Unknown"

    var displayName: String { rawValue }
}

enum StreamHDR: String, Hashable, Sendable {
    case hdr10 = "HDR10"
    case hdr10Plus = "HDR10+"
    case dolbyVision = "Dolby Vision"

    var displayName: String { rawValue }
}
