import Foundation
import Observation
#if canImport(zlib)
import zlib
#endif

// MARK: - Subtitle Service

@Observable
final class SubtitleService {

    // MARK: Singleton
    static let shared = SubtitleService()

    // MARK: Configuration
    var subdlApiKey: String = ""
    var openSubtitlesApiKey: String = ""

    // MARK: State
    var isLoading: Bool = false
    var availableTracks: [SubtitleTrackItem] = []
    var error: String?

    // MARK: Private
    private let session: URLSession
    private let cacheDirectory: URL

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = caches.appendingPathComponent("AuraSubtitles", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Search All Subtitles

    /// Fetch external subtitles across SubDL, OpenSubtitles, and Wyzie
    func fetchSubtitles(
        imdbId: String,
        season: Int? = nil,
        episode: Int? = nil,
        preferredLanguage: String = "ar"
    ) async -> [SubtitleTrackItem] {
        isLoading = true
        error = nil
        availableTracks = []

        defer { isLoading = false }

        var results: [SubtitleTrackItem] = []

        // Clean IMDb ID (ensure "tt" prefix)
        let cleanImdb = imdbId.hasPrefix("tt") ? imdbId : "tt\(imdbId)"

        // 1. Fetch from Wyzie (no key needed, fast)
        let wyzieTracks = await fetchFromWyzie(imdbId: cleanImdb, season: season, episode: episode)
        results.append(contentsOf: wyzieTracks)

        // 2. Fetch from SubDL (if key configured)
        if !subdlApiKey.isEmpty {
            let subdlTracks = await fetchFromSubDL(imdbId: cleanImdb, season: season, episode: episode)
            results.append(contentsOf: subdlTracks)
        }

        // 3. Fetch from OpenSubtitles (if key configured)
        if !openSubtitlesApiKey.isEmpty {
            let openSubTracks = await fetchFromOpenSubtitles(imdbId: cleanImdb, season: season, episode: episode)
            results.append(contentsOf: openSubTracks)
        }

        // Sort: Preferred language first (e.g. Arabic), then English, then others
        let sorted = results.sorted { a, b in
            let aPref = a.languageCode.lowercased() == preferredLanguage.lowercased()
            let bPref = b.languageCode.lowercased() == preferredLanguage.lowercased()
            if aPref != bPref { return aPref }

            let aEng = a.languageCode.lowercased() == "en"
            let bEng = b.languageCode.lowercased() == "en"
            if aEng != bEng { return aEng }

            return a.name < b.name
        }

        availableTracks = sorted
        return sorted
    }

    // MARK: - Wyzie Provider

    private func fetchFromWyzie(imdbId: String, season: Int?, episode: Int?) async -> [SubtitleTrackItem] {
        var urlComponents = URLComponents(string: "https://sub.wyzie.ru/search")
        var queryItems = [
            URLQueryItem(name: "id", value: imdbId),
            URLQueryItem(name: "language", value: "ar,en")
        ]
        if let s = season, let e = episode {
            queryItems.append(URLQueryItem(name: "season", value: "\(s)"))
            queryItems.append(URLQueryItem(name: "episode", value: "\(e)"))
        }
        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else { return [] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }

            let items = try JSONDecoder().decode([WyzieSubtitleItem].self, from: data)
            return items.compactMap { item -> SubtitleTrackItem? in
                guard let dlUrlString = item.url, let dlUrl = URL(string: dlUrlString) else { return nil }
                let langCode = item.language?.lowercased() ?? "en"
                let langName = langCode == "ar" ? "Arabic" : "English"
                return SubtitleTrackItem(
                    id: "wyzie_\(item.id ?? UUID().uuidString)",
                    name: item.title ?? "\(langName) Subtitle",
                    language: langName,
                    languageCode: langCode,
                    source: .wyzie,
                    downloadURL: dlUrl,
                    releaseInfo: item.title,
                    hearingImpaired: false,
                    isEmbedded: false,
                    embeddedTrackId: nil
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - SubDL Provider

    private func fetchFromSubDL(imdbId: String, season: Int?, episode: Int?) async -> [SubtitleTrackItem] {
        guard !subdlApiKey.isEmpty else { return [] }

        var urlComponents = URLComponents(string: "https://api.subdl.com/api/v1/subtitles")
        var queryItems = [
            URLQueryItem(name: "api_key", value: subdlApiKey),
            URLQueryItem(name: "imdb_id", value: imdbId),
            URLQueryItem(name: "languages", value: "ar,en")
        ]
        if let s = season, let e = episode {
            queryItems.append(URLQueryItem(name: "type", value: "tv"))
            queryItems.append(URLQueryItem(name: "season_number", value: "\(s)"))
            queryItems.append(URLQueryItem(name: "episode_number", value: "\(e)"))
        } else {
            queryItems.append(URLQueryItem(name: "type", value: "movie"))
        }
        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else { return [] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }

            let responseObj = try JSONDecoder().decode(SubDLResponse.self, from: data)
            let subList = responseObj.subtitles ?? responseObj.results?.first?.subtitles ?? []

            return subList.compactMap { item -> SubtitleTrackItem? in
                guard let subUrlStr = item.url else { return nil }
                let fullUrlStr = subUrlStr.hasPrefix("http") ? subUrlStr : "https://dl.subdl.com\(subUrlStr)"
                guard let dlUrl = URL(string: fullUrlStr) else { return nil }

                let lang = item.lang ?? "Arabic"
                let langCode = lang.lowercased().contains("arab") ? "ar" : "en"

                return SubtitleTrackItem(
                    id: "subdl_\(UUID().uuidString)",
                    name: item.name ?? item.releaseName ?? "SubDL Subtitle",
                    language: lang,
                    languageCode: langCode,
                    source: .subdl,
                    downloadURL: dlUrl,
                    releaseInfo: item.releaseName,
                    hearingImpaired: item.hi ?? false,
                    isEmbedded: false,
                    embeddedTrackId: nil
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - OpenSubtitles Provider

    private func fetchFromOpenSubtitles(imdbId: String, season: Int?, episode: Int?) async -> [SubtitleTrackItem] {
        guard !openSubtitlesApiKey.isEmpty else { return [] }

        let cleanImdbNumeric = imdbId.replacingOccurrences(of: "tt", with: "")
        var urlComponents = URLComponents(string: "https://api.opensubtitles.com/api/v1/subtitles")
        var queryItems = [
            URLQueryItem(name: "imdb_id", value: cleanImdbNumeric),
            URLQueryItem(name: "languages", value: "ar,en")
        ]
        if let s = season, let e = episode {
            queryItems.append(URLQueryItem(name: "season_number", value: "\(s)"))
            queryItems.append(URLQueryItem(name: "episode_number", value: "\(e)"))
        }
        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else { return [] }

        var request = URLRequest(url: url)
        request.addValue(openSubtitlesApiKey, forHTTPHeaderField: "Api-Key")
        request.addValue("AuraTV v1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }

            let result = try JSONDecoder().decode(OpenSubtitlesResponse.self, from: data)
            guard let items = result.data else { return [] }

            return items.compactMap { item -> SubtitleTrackItem? in
                guard let file = item.attributes?.files?.first, let fileId = file.fileId else { return nil }
                let langCode = item.attributes?.language?.lowercased() ?? "en"
                let langName = langCode == "ar" ? "Arabic" : "English"
                let release = item.attributes?.release ?? file.fileName

                // Temporary download URL proxy or direct API download endpoint
                let downloadUrl = URL(string: "https://api.opensubtitles.com/api/v1/download?file_id=\(fileId)")

                return SubtitleTrackItem(
                    id: "opensub_\(item.id ?? "\(fileId)")",
                    name: release ?? "\(langName) Subtitle",
                    language: langName,
                    languageCode: langCode,
                    source: .openSubtitles,
                    downloadURL: downloadUrl,
                    releaseInfo: release,
                    hearingImpaired: item.attributes?.hearingImpaired ?? false,
                    isEmbedded: false,
                    embeddedTrackId: nil,
                    openSubtitlesFileId: fileId
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - Download & Parse Subtitles

    /// Download external subtitle file and parse into structured cues
    func loadAndParseCues(for track: SubtitleTrackItem) async throws -> [AuraSubtitleCue] {
        let cacheFile = cacheDirectory.appendingPathComponent("\(track.id).srt")

        let rawContent: String
        if FileManager.default.fileExists(atPath: cacheFile.path) {
            rawContent = try String(contentsOf: cacheFile, encoding: .utf8)
        } else {
            var downloadData: Data

            // OpenSubtitles 2-step download flow
            if track.source == .openSubtitles, let fileId = track.openSubtitlesFileId, !openSubtitlesApiKey.isEmpty {
                var postReq = URLRequest(url: URL(string: "https://api.opensubtitles.com/api/v1/download")!)
                postReq.httpMethod = "POST"
                postReq.addValue(openSubtitlesApiKey, forHTTPHeaderField: "Api-Key")
                postReq.addValue("AuraTV v1.0", forHTTPHeaderField: "User-Agent")
                postReq.addValue("application/json", forHTTPHeaderField: "Content-Type")
                postReq.addValue("application/json", forHTTPHeaderField: "Accept")
                let body = ["file_id": fileId]
                postReq.httpBody = try? JSONSerialization.data(withJSONObject: body)

                let (postData, postResp) = try await session.data(for: postReq)
                guard let postHttp = postResp as? HTTPURLResponse, (200...299).contains(postHttp.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                let dlResult = try JSONDecoder().decode(OpenSubtitlesDownloadResponse.self, from: postData)
                guard let link = dlResult.link, let directUrl = URL(string: link) else {
                    throw URLError(.cannotParseResponse)
                }

                let (fileBytes, fileResp) = try await session.data(from: directUrl)
                guard let fileHttp = fileResp as? HTTPURLResponse, (200...299).contains(fileHttp.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                downloadData = fileBytes
            } else {
                guard let url = track.downloadURL else { return [] }
                var request = URLRequest(url: url)
                if track.source == .openSubtitles && !openSubtitlesApiKey.isEmpty {
                    request.addValue(openSubtitlesApiKey, forHTTPHeaderField: "Api-Key")
                    request.addValue("AuraTV v1.0", forHTTPHeaderField: "User-Agent")
                }

                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                downloadData = data
            }

            // Check if downloaded data is a ZIP archive (SubDL zip packages)
            if downloadData.count > 4 && downloadData.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]) {
                if let extractedData = extractSrtFromZip(downloadData) {
                    downloadData = extractedData
                }
            }

            // Attempt UTF-8, Windows-1256 (Arabic), or Latin-1
            let windows1256Encoding = String.Encoding(
                rawValue: CFStringConvertEncodingToNSStringEncoding(
                    CFStringEncoding(CFStringEncodings.windowsArabic.rawValue)
                )
            )
            if let str = String(data: downloadData, encoding: .utf8) {
                rawContent = str
            } else if let str = String(data: downloadData, encoding: windows1256Encoding) {
                rawContent = str
            } else if let str = String(data: downloadData, encoding: .isoLatin1) {
                rawContent = str
            } else {
                rawContent = String(decoding: downloadData, as: UTF8.self)
            }

            // Save to cache
            try? rawContent.write(to: cacheFile, atomically: true, encoding: .utf8)
        }

        return parseSRTorVTT(rawContent)
    }

    // MARK: - Zip Extraction Helper (SubDL ZIP Support)

    private func extractSrtFromZip(_ data: Data) -> Data? {
        var offset = 0
        while offset + 30 <= data.count {
            let sig = data.subdata(in: offset..<offset+4)
            if sig != Data([0x50, 0x4B, 0x03, 0x04]) {
                break
            }

            let compressionMethod = data.subdata(in: offset+8..<offset+10).withUnsafeBytes { $0.load(as: UInt16.self) }
            let compressedSize = Int(data.subdata(in: offset+18..<offset+22).withUnsafeBytes { $0.load(as: UInt32.self) })
            let uncompressedSize = Int(data.subdata(in: offset+22..<offset+26).withUnsafeBytes { $0.load(as: UInt32.self) })
            let fileNameLen = Int(data.subdata(in: offset+26..<offset+28).withUnsafeBytes { $0.load(as: UInt16.self) })
            let extraFieldLen = Int(data.subdata(in: offset+28..<offset+30).withUnsafeBytes { $0.load(as: UInt16.self) })

            let fileDataStart = offset + 30 + fileNameLen + extraFieldLen
            guard fileDataStart + compressedSize <= data.count else { break }

            let fileNameData = data.subdata(in: offset+30..<offset+30+fileNameLen)
            let fileName = String(data: fileNameData, encoding: .utf8) ?? ""

            if fileName.lowercased().hasSuffix(".srt") || fileName.lowercased().hasSuffix(".vtt") || fileName.lowercased().hasSuffix(".sub") {
                let fileCompressedData = data.subdata(in: fileDataStart..<fileDataStart+compressedSize)
                if compressionMethod == 0 {
                    return fileCompressedData
                } else if compressionMethod == 8 {
                    #if canImport(zlib)
                    if let decompressed = decompressRawDeflate(fileCompressedData, expectedSize: uncompressedSize) {
                        return decompressed
                    }
                    #endif
                    return fileCompressedData
                }
            }

            offset = fileDataStart + compressedSize
        }
        return nil
    }

    #if canImport(zlib)
    private func decompressRawDeflate(_ data: Data, expectedSize: Int) -> Data? {
        var stream = z_stream()
        var status = inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        let chunkSize = 64 * 1024

        return data.withUnsafeBytes { rawIn -> Data? in
            guard let inPtr = rawIn.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return nil }
            stream.next_in = UnsafeMutablePointer(mutating: inPtr)
            stream.avail_in = uInt(data.count)

            var outputData = Data()
            var buffer = [UInt8](repeating: 0, count: chunkSize)

            while stream.avail_in > 0 {
                buffer.withUnsafeMutableBytes { rawOut in
                    guard let outPtr = rawOut.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return }
                    stream.next_out = outPtr
                    stream.avail_out = uInt(chunkSize)

                    status = inflate(&stream, Z_NO_FLUSH)
                    let bytesWritten = chunkSize - Int(stream.avail_out)
                    if bytesWritten > 0, let outBytes = rawOut.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                        outputData.append(outBytes, count: bytesWritten)
                    }
                }

                if status == Z_STREAM_END { break }
                if status != Z_OK && status != Z_BUF_ERROR { break }
            }

            return outputData.isEmpty ? nil : outputData
        }
    }
    #endif

    // MARK: - SRT / VTT Parser

    /// Parses raw SRT or WebVTT content into [AuraSubtitleCue]
    func parseSRTorVTT(_ content: String) -> [AuraSubtitleCue] {
        var cues: [AuraSubtitleCue] = []

        // Normalize line breaks
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Split by empty lines
        let blocks = normalized.components(separatedBy: "\n\n")
        var cueIndex = 1

        let timeRegex = try? NSRegularExpression(
            pattern: #"(\d{1,2}:)?(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{1,2}:)?(\d{2}):(\d{2})[,.](\d{3})"#,
            options: []
        )

        for block in blocks {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            guard !lines.isEmpty else { continue }

            var timeLineIndex: Int?
            var matchRange: NSTextCheckingResult?

            // Find line with timestamp
            for (idx, line) in lines.enumerated() {
                if let match = timeRegex?.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) {
                    timeLineIndex = idx
                    matchRange = match
                    break
                }
            }

            guard let tIndex = timeLineIndex, matchRange != nil else { continue }

            let timeLine = lines[tIndex]

            // Extract start & end times
            let parts = timeLine.components(separatedBy: "-->")
            guard parts.count >= 2 else { continue }

            let startStr = parts[0].trimmingCharacters(in: .whitespaces)
            let endStr = parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""

            guard let startTime = parseTimestamp(startStr),
                  let endTime = parseTimestamp(endStr) else { continue }

            // Content lines (all lines after timestamp line)
            let textLines = lines.dropFirst(tIndex + 1)
            let rawText = textLines.joined(separator: "\n")
            let cleanedText = cleanSubtitleFormatting(rawText)

            guard !cleanedText.isEmpty else { continue }

            let isArabic = containsArabic(cleanedText)

            let cue = AuraSubtitleCue(
                id: cueIndex,
                startTime: startTime,
                endTime: endTime,
                text: cleanedText,
                processedText: nil,
                isArabic: isArabic
            )

            cues.append(cue)
            cueIndex += 1
        }

        return cues
    }

    // MARK: - Helper Functions

    /// Convert "00:01:23,456" or "01:23.456" to seconds
    private func parseTimestamp(_ str: String) -> TimeInterval? {
        let clean = str.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        let parts = clean.components(separatedBy: ":")

        if parts.count == 3 {
            guard let h = Double(parts[0]),
                  let m = Double(parts[1]),
                  let s = Double(parts[2]) else { return nil }
            return (h * 3600.0) + (m * 60.0) + s
        } else if parts.count == 2 {
            guard let m = Double(parts[0]),
                  let s = Double(parts[1]) else { return nil }
            return (m * 60.0) + s
        }
        return nil
    }

    /// Strip HTML and ASS/SSA tags
    private func cleanSubtitleFormatting(_ text: String) -> String {
        var str = text
        // Strip HTML tags: <i>, </b>, <font color="...">
        str = str.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Strip ASS styling tags: {\an8}, {y:i}
        str = str.replacingOccurrences(of: "\\{[^\\}]+\\}", with: "", options: .regularExpression)
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Check if text contains Arabic Unicode characters
    private func containsArabic(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            // Arabic standard block, supplement, presentation forms A & B
            if (0x0600...0x06FF).contains(scalar.value) ||
               (0x0750...0x077F).contains(scalar.value) ||
               (0x08A0...0x08FF).contains(scalar.value) ||
               (0xFB50...0xFDFF).contains(scalar.value) ||
               (0xFE70...0xFEFF).contains(scalar.value) {
                return true
            }
        }
        return false
    }
}
