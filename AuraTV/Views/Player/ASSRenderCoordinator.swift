import Foundation
import SwiftUI
import Combine
#if canImport(SwiftAssRenderer)
import SwiftAssRenderer
#endif
#if canImport(AetherEngine)
import AetherEngine
#endif

// MARK: - ASS / SSA Styled Subtitle Coordinator (SwiftAssRenderer + libass)

@MainActor
final class ASSRenderCoordinator: ObservableObject {
    @Published private(set) var isRenderingASS: Bool = false

    #if canImport(SwiftAssRenderer)
    private(set) var renderer: AssSubtitlesRenderer?
    private let fontsDirectory: URL
    private let fontsCacheDirectory: URL
    private var installedAttachmentNames: Set<String> = []
    private var loadedExternalKey: String?
    private var activeEmbeddedTrackKey: String?
    private var lastLoadedScriptHash: Int?

    #if canImport(AetherEngine)
    private var scriptBuilder: ASSScriptBuilder?
    #endif
    #endif

    init() {
        #if canImport(SwiftAssRenderer)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let fontsDir = caches.appendingPathComponent("AuraASSFonts", isDirectory: true)
        let fontsCacheDir = caches.appendingPathComponent("AuraASSFontsCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: fontsCacheDir, withIntermediateDirectories: true)
        self.fontsDirectory = fontsDir
        self.fontsCacheDirectory = fontsCacheDir
        copyBundledFonts(to: fontsDir)
        self.renderer = makeRenderer()
        #endif
    }

    // MARK: - External ASS / SSA Track Loading

    func loadExternalASS(
        content: String,
        trackKey: String,
        currentTime: Double,
        manualOffset: Double
    ) {
        #if canImport(SwiftAssRenderer)
        activeEmbeddedTrackKey = nil
        #if canImport(AetherEngine)
        scriptBuilder = nil
        #endif

        guard renderer != nil else { return }
        if loadedExternalKey != trackKey {
            loadedExternalKey = trackKey
            lastLoadedScriptHash = content.hashValue
            renderer?.loadTrack(content: content)
        }
        isRenderingASS = true
        renderer?.setTimeOffset(max(0, currentTime - manualOffset))
        #endif
    }

    func updateExternalTimeOffset(currentTime: Double, manualOffset: Double) {
        #if canImport(SwiftAssRenderer)
        guard isRenderingASS, loadedExternalKey != nil else { return }
        renderer?.setTimeOffset(max(0, currentTime - manualOffset))
        #endif
    }

    func clearExternalASS() {
        #if canImport(SwiftAssRenderer)
        guard loadedExternalKey != nil else { return }
        loadedExternalKey = nil
        lastLoadedScriptHash = nil
        renderer?.freeTrack()
        if activeEmbeddedTrackKey == nil {
            isRenderingASS = false
        }
        #endif
    }

    func clearEmbeddedASS() {
        #if canImport(SwiftAssRenderer)
        guard activeEmbeddedTrackKey != nil else { return }
        activeEmbeddedTrackKey = nil
        lastLoadedScriptHash = nil
        #if canImport(AetherEngine)
        scriptBuilder = nil
        #endif
        if loadedExternalKey == nil {
            renderer?.freeTrack()
            isRenderingASS = false
        }
        #endif
    }

    func clearAll() {
        #if canImport(SwiftAssRenderer)
        loadedExternalKey = nil
        activeEmbeddedTrackKey = nil
        lastLoadedScriptHash = nil
        #if canImport(AetherEngine)
        scriptBuilder = nil
        #endif
        renderer?.freeTrack()
        isRenderingASS = false
        #endif
    }

    // MARK: - AetherEngine Embedded ASS / Font Attachments

    #if canImport(AetherEngine)
    func installFontAttachments(_ attachments: [FontAttachment]) {
        #if canImport(SwiftAssRenderer)
        var didWriteNewFont = false
        for attachment in attachments {
            let safeName = (attachment.filename as NSString).lastPathComponent
            guard !safeName.isEmpty, !installedAttachmentNames.contains(safeName) else { continue }
            let targetURL = fontsDirectory.appendingPathComponent(safeName)
            if (try? attachment.data.write(to: targetURL, options: .atomic)) != nil {
                installedAttachmentNames.insert(safeName)
                didWriteNewFont = true
            }
        }

        if didWriteNewFont {
            renderer = makeRenderer()
            // Force reload on the next sync tick so new attachment fonts take effect.
            lastLoadedScriptHash = nil
            loadedExternalKey = nil
        }
        #endif
    }

    @discardableResult
    func syncEmbeddedASS(
        track: TrackInfo?,
        cues: [SubtitleCue],
        sourceTime: Double,
        manualOffset: Double
    ) -> Bool {
        #if canImport(SwiftAssRenderer)
        guard let track,
              (track.codec.lowercased() == "ass" || track.codec.lowercased() == "ssa"),
              let header = track.assHeader,
              !header.isEmpty else {
            clearEmbeddedASS()
            return false
        }

        loadedExternalKey = nil
        let key = "\(track.id)|\(header.hashValue)"

        if activeEmbeddedTrackKey != key || scriptBuilder == nil {
            activeEmbeddedTrackKey = key
            let builder = ASSScriptBuilder(header: header)
            self.scriptBuilder = builder
            for cue in cues {
                if let rawText = cue.text, !rawText.isEmpty {
                    builder.add(rawEventText: rawText, start: cue.startTime, end: cue.endTime)
                }
            }
            let fullScript = builder.script()
            lastLoadedScriptHash = fullScript.hashValue
            renderer?.loadTrack(content: fullScript)
        } else if let builder = scriptBuilder {
            var addedNew = false
            for cue in cues {
                if let rawText = cue.text, !rawText.isEmpty {
                    if builder.add(rawEventText: rawText, start: cue.startTime, end: cue.endTime) {
                        addedNew = true
                    }
                }
            }
            if addedNew || lastLoadedScriptHash == nil {
                let fullScript = builder.script()
                let newHash = fullScript.hashValue
                if newHash != lastLoadedScriptHash {
                    lastLoadedScriptHash = newHash
                    renderer?.reloadTrack(content: fullScript)
                }
            }
        }

        isRenderingASS = true
        renderer?.setTimeOffset(max(0, sourceTime - manualOffset))
        return true
        #else
        return false
        #endif
    }
    #endif

    // MARK: - Helpers

    #if canImport(SwiftAssRenderer)
    private func makeRenderer() -> AssSubtitlesRenderer {
        let preferredDefault = fontsDirectory.appendingPathComponent("IBMPlexSansArabic-Regular.ttf")
        let defaultFontPath = FileManager.default.fileExists(atPath: preferredDefault.path)
            ? preferredDefault.path
            : nil

        let config = FontConfig(
            fontsPath: fontsDirectory,
            fontsCachePath: fontsCacheDirectory,
            defaultFontName: defaultFontPath,
            defaultFontFamily: "IBM Plex Sans Arabic",
            fontProvider: .fontConfig
        )
        return AssSubtitlesRenderer(fontConfig: config)
    }

    private func copyBundledFonts(to destinationDir: URL) {
        var fontURLs: [URL] = []
        if let rootTTF = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) {
            fontURLs.append(contentsOf: rootTTF)
        }
        if let nestedTTF = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") {
            fontURLs.append(contentsOf: nestedTTF)
        }
        if let rootOTF = Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) {
            fontURLs.append(contentsOf: rootOTF)
        }

        for srcURL in fontURLs {
            let destURL = destinationDir.appendingPathComponent(srcURL.lastPathComponent)
            if !FileManager.default.fileExists(atPath: destURL.path) {
                try? FileManager.default.copyItem(at: srcURL, to: destURL)
            }
        }
    }
    #endif
}
