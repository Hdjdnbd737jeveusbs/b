import AVFoundation
import Foundation
import SwiftData
import Observation
import CoreGraphics

// MARK: - Aspect Ratio & Live Playback Stats

enum AspectRatioMode: String, CaseIterable {
    case fit = "Fit"
    case fill = "Fill"
    case stretch = "Stretch"
}

struct PlaybackStats: Equatable {
    var videoCodec: String = "—"
    var resolution: String = "—"
    var dynamicRange: String = "SDR"
    var observedFPS: String = "—"
    var droppedFrames: Int = 0
    var audioCodec: String = "—"
    var audioChannels: String = "—"
    var audioBitrate: String = "—"
    var forwardBuffer: String = "—"
    var throughput: String = "—"
    var avSyncGap: String = "—"
    var activeEngine: String = "AetherEngine"
}

// MARK: - Audio/Subtitle Track Model

struct MediaTrack: Identifiable, Hashable {
    let id: Int
    let name: String
    let language: String?
    let isDefault: Bool

    var displayName: String {
        if let lang = language, !lang.isEmpty {
            return "\(lang) · \(name)"
        }
        return name
    }
}

// MARK: - Player ViewModel

@Observable
final class PlayerViewModel {

    // MARK: - Playback State

    var streamURL: URL?
    var isPlaying: Bool = false
    var isBuffering: Bool = true
    var currentTime: Double = 0
    var totalDuration: Double = 0
    var playbackRate: Double = 1.0
    var seekTrigger: Double?
    var isPreviewMode: Bool = false
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
    var audioSyncOffsetMs: Int = 0
    var playbackError: String?
    var videoDynamicRangeBadge: String?

    // MARK: - Live Stats & Quick Controls

    var showLiveStatsHUD: Bool = false
    var playbackStats = PlaybackStats()
    var aspectRatioMode: AspectRatioMode = .fit
    static let speedOptions: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    static let sleepTimerOptions: [Int] = [0, 15, 30, 45, 60, -1] // -1 = End of Episode
    var sleepTimerOption: Int = 0
    var sleepTimerRemainingSeconds: Int?
    private var sleepTimerCountdown: Timer?

    var speedDisplayText: String {
        playbackRate == 1.0 ? "1.0x" : String(format: "%gx", playbackRate)
    }

    var sleepTimerDisplayText: String {
        if sleepTimerOption == 0 { return "Off" }
        if sleepTimerOption == -1 { return "End of Episode" }
        if let remaining = sleepTimerRemainingSeconds, remaining > 0 {
            let mins = remaining / 60
            let secs = remaining % 60
            return String(format: "%d:%02d", mins, secs)
        }
        return "\(sleepTimerOption)m"
    }

    // MARK: - Streams & Quality

    var availableStreams: [StremioStream] = []
    var selectedStream: StremioStream?
    var showStreamPicker: Bool = false
    var preferredQuality: String = "4K"
    var previewBadges: [String]?

    var activeTechBadges: [String] {
        if let previewBadges, !previewBadges.isEmpty {
            return previewBadges
        }
        if let badges = selectedStream?.parsedInfo.techBadges, !badges.isEmpty {
            return badges
        }
        return ["4K", "HDR10", "5.1"]
    }

    // MARK: - Track Selection

    var availableAudioTracks: [MediaTrack] = []
    var availableSubtitleTracks: [MediaTrack] = []
    var selectedAudioTrackId: Int = 0
    var selectedSubtitleTrackId: Int = -1 // -1 = off

    // MARK: - Subtitles, Styling & Sync State

    var externalSubtitleTracks: [SubtitleTrackItem] = []
    var selectedExternalSubtitle: SubtitleTrackItem?
    var activeCues: [AuraSubtitleCue] = []
    var currentSubtitleCue: AuraSubtitleCue?
    var activeEmbeddedTextCue: AuraSubtitleCue?
    var currentBitmapSubtitle: CGImage?
    private var subtitleRevision = 0
    var referenceEmbeddedCues: [AuraSubtitleCue] = []
    var subtitleSyncSettings: SubtitleSyncSettings = .defaultSettings
    var subtitleStyle: SubtitleStyle = .defaultStyle
    var isFetchingSubtitles: Bool = false
    var isSyncingSubtitles: Bool = false
    var syncStatusMessage: String?
    var showSubtitleStyleSheet: Bool = false
    var showSubtitleSyncSheet: Bool = false
    var showSyncToLineSheet: Bool = false
    var externalASSContent: String?
    var isActiveEmbeddedASS: Bool = false
    var embeddedPlainCuesForSync: [AuraSubtitleCue] = []
    var aiTranslationConfig: SubtitleTranslationConfig = .disabled
    var translatedCueTexts: [Int: String] = [:]
    private var translationTask: Task<Void, Never>?
    private var inFlightTranslationIds: Set<Int> = []
    private var activeEmbeddedTrackLanguageCode: String?
    var subtitleSearchText: String = ""
    var imdbId: String = ""
    var preferredSubtitleLanguage: String = "ar"

    var isASSTrackActive: Bool {
        externalASSContent != nil || (selectedExternalSubtitle == nil && isActiveEmbeddedASS)
    }

    var syncableCueCandidates: [AuraSubtitleCue] {
        !activeCues.isEmpty ? activeCues : embeddedPlainCuesForSync
    }

    var filteredSubtitleTracks: [SubtitleTrackItem] {
        if subtitleSearchText.isEmpty {
            return externalSubtitleTracks
        }
        return externalSubtitleTracks.filter {
            $0.name.localizedCaseInsensitiveContains(subtitleSearchText) ||
            $0.language.localizedCaseInsensitiveContains(subtitleSearchText) ||
            ($0.releaseInfo?.localizedCaseInsensitiveContains(subtitleSearchText) ?? false)
        }
    }

    // MARK: - HUD State

    var isHUDVisible: Bool = true
    var showAudioPicker: Bool = false
    var showSubtitlePicker: Bool = false
    var showOptionsMenu: Bool = false
    var showInfoPanel: Bool = false

    var hasActiveModalOverlay: Bool {
        showAudioPicker || showSubtitlePicker || showOptionsMenu || showInfoPanel || showSubtitleSyncSheet || showSubtitleStyleSheet || showSyncToLineSheet || showStreamPicker
    }

    // MARK: - Skip Intro / Credits & Up Next

    var skipIntroMode: String = "Skip After Delay"
    var skipRecapMode: String = "Skip After Delay"
    var skipCreditsMode: String = "Show Button"
    var skipDelaySeconds: Int = 8
    var nextEpisodeBehavior: String = "On · 10 s"

    var skipIntroDismissed: Bool = false
    var skipCreditsDismissed: Bool = false
    var upNextDismissed: Bool = false
    var nextEpisode: TMDBEpisode?
    var onPlayNextEpisode: ((TMDBEpisode) -> Void)?

    private var didAutoSkipIntro: Bool = false
    private var upNextTriggered: Bool = false

    private var introRange: Range<Double>?

    @MainActor
    func loadIntroMarker(for url: URL) async {
        introRange = nil
        guard mediaType == "series", skipIntroMode != "Off" else { return }
        let asset = AVURLAsset(url: url)
        guard let chapters = try? await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: Locale.preferredLanguages) else { return }
        let introNames = ["intro", "opening", "opening credits", "opening theme", "مقدمة", "المقدمة"]
        for chapter in chapters {
            let titles = AVMetadataItem.metadataItems(from: chapter.items, withKey: AVMetadataKey.commonKeyTitle, keySpace: .common)
            for item in titles {
                guard let title = try? await item.load(.stringValue),
                      introNames.contains(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else { continue }
                let start = chapter.timeRange.start.seconds
                let end = CMTimeRangeGetEnd(chapter.timeRange).seconds
                guard !Task.isCancelled, streamURL == url, start.isFinite, end.isFinite, start >= 0, end > start else { return }
                introRange = start..<end
                return
            }
        }
    }

    var showSkipIntroPill: Bool {
        mediaType == "series"
            && !skipIntroDismissed
            && skipIntroMode != "Off"
            && introRange?.contains(currentTime) == true
    }

    var skipIntroCountdownRemaining: Int? {
        guard let introRange, showSkipIntroPill, skipIntroMode == "Skip After Delay" else { return nil }
        return max(0, skipDelaySeconds - Int(currentTime - introRange.lowerBound))
    }

    var showSkipCreditsPill: Bool {
        totalDuration > 180
            && (totalDuration - currentTime) <= 75
            && (totalDuration - currentTime) > 45
            && !skipCreditsDismissed
            && skipCreditsMode != "Off"
            && !showUpNextOverlay
    }

    var showUpNextOverlay: Bool {
        mediaType == "series"
            && nextEpisode != nil
            && !upNextDismissed
            && nextEpisodeBehavior != "Off"
            && totalDuration > 180
            && (totalDuration - currentTime) <= Double(nextEpisodeBehavior.contains("5") ? 5 : 10)
    }

    var upNextCountdownRemaining: Int {
        let configured = nextEpisodeBehavior.contains("5") ? 5 : 10
        let remainingUntilEnd = max(0, Int(ceil(totalDuration - currentTime)))
        return min(configured, remainingUntilEnd)
    }

    // MARK: - Media Info

    var title: String = ""
    var overview: String = ""
    var backdropPath: String?
    var posterPath: String?
    var tmdbId: Int = 0
    var mediaType: String = "movie"
    var seasonNumber: Int?
    var episodeNumber: Int?
    var episodeTitle: String?
    var episodeStillPath: String?

    // MARK: - Resume

    var resumeFromTime: Double = 0

    // MARK: - Timers

    private var hudHideTimer: Timer?
    private var progressSaveTimer: Timer?
    private var saveContext: ModelContext?

    // MARK: - Computed Properties

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return min(max(currentTime / totalDuration, 0), 1)
    }

    var currentTimeFormatted: String {
        formatTime(currentTime)
    }

    var remainingTimeFormatted: String {
        let remaining = max(totalDuration - currentTime, 0)
        return "-\(formatTime(remaining))"
    }

    var hasStartedPlayback: Bool {
        (!isBuffering && totalDuration > 0) || isPreviewMode
    }

    // MARK: - Setup

    func configure(
        url: URL,
        title: String,
        overview: String = "",
        backdropPath: String?,
        posterPath: String?,
        tmdbId: Int,
        mediaType: String,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil,
        episodeStillPath: String? = nil,
        resumeFrom: Double = 0,
        imdbId: String = "",
        availableStreams: [StremioStream] = [],
        selectedStream: StremioStream? = nil,
        nextEpisode: TMDBEpisode? = nil,
        onPlayNextEpisode: ((TMDBEpisode) -> Void)? = nil
    ) {
        self.isPreviewMode = false
        self.streamURL = url
        self.title = title
        self.overview = overview
        self.backdropPath = backdropPath
        self.posterPath = posterPath
        self.tmdbId = tmdbId
        self.mediaType = mediaType
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
        self.episodeStillPath = episodeStillPath
        self.resumeFromTime = resumeFrom
        self.imdbId = imdbId
        self.availableStreams = availableStreams
        self.selectedStream = selectedStream
        self.nextEpisode = nextEpisode
        self.onPlayNextEpisode = onPlayNextEpisode
        self.isBuffering = true
        self.isPlaying = false
        self.playbackError = nil
        self.videoDynamicRangeBadge = nil
        self.activeEmbeddedTextCue = nil
        self.currentBitmapSubtitle = nil
        self.externalASSContent = nil
        self.isActiveEmbeddedASS = false
        self.embeddedPlainCuesForSync = []
        self.translatedCueTexts = [:]
        self.inFlightTranslationIds = []
        self.translationTask?.cancel()
        self.translationTask = nil
        self.activeEmbeddedTrackLanguageCode = nil
        self.availableAudioTracks = []
        self.availableSubtitleTracks = []
        self.selectedSubtitleTrackId = -1
        self.currentTime = resumeFrom
        self.skipIntroDismissed = false
        self.skipCreditsDismissed = false
        self.upNextDismissed = false
        self.didAutoSkipIntro = false
        self.upNextTriggered = false

        Task {
            await fetchSubtitles()
        }
    }

    enum PreviewScreenMode {
        case hud
        case subtitlesMenu
        case subtitleSync
        case loading
    }

    /// Configures realistic Skyfall demo playback state for CI previews.
    @MainActor
    func configurePreviewHUD(mode: PreviewScreenMode = .hud) {
        self.isPreviewMode = mode != .loading
        self.title = "Skyfall"
        self.overview = "When Bond's latest assignment goes gravely wrong and agents around the world are exposed, MI6 itself comes under attack."
        self.tmdbId = 37724
        self.mediaType = "movie"
        self.backdropPath = "/wkA622CCN2X0uwpgqYEOnUYEDf5.jpg"
        self.currentTime = 2348
        self.totalDuration = 8589
        self.isBuffering = mode == .loading
        self.isPlaying = mode != .loading
        self.isHUDVisible = mode != .loading
        self.previewBadges = ["4K", "Dolby Vision", "5.1"]
        self.availableStreams = [
            StremioStream(
                name: "Torrentio | RD+",
                title: "Skyfall.2012.2160p.UHD.BluRay.REMUX.DV.HDR10.TrueHD.Atmos.7.1",
                description: "4K DV HDR10 42.6 GB",
                url: "https://example.com/skyfall-4k.mkv"
            )
        ]
        self.selectedStream = availableStreams.first
        self.availableAudioTracks = [
            MediaTrack(id: 1, name: "English · Dolby TrueHD Atmos 7.1", language: "en", isDefault: true),
            MediaTrack(id: 2, name: "English · AC3 5.1", language: "en", isDefault: false)
        ]
        self.selectedAudioTrackId = 1

        let track1 = SubtitleTrackItem(
            id: "preview_ar_1",
            name: "Arabic · RaYY00aN · BluRay 1080p SDR...",
            language: "Arabic",
            languageCode: "ar",
            source: .subdl,
            downloadURL: nil,
            releaseInfo: "RaYY00aN · BluRay 1080p SDR...",
            hearingImpaired: false,
            isEmbedded: false,
            embeddedTrackId: nil
        )
        let track2 = SubtitleTrackItem(
            id: "preview_ar_2",
            name: "Arabic · Bander Alhlbaney · BluRay 720p...",
            language: "Arabic",
            languageCode: "ar",
            source: .subdl,
            downloadURL: nil,
            releaseInfo: "Bander Alhlbaney · BluRay 720p...",
            hearingImpaired: false,
            isEmbedded: false,
            embeddedTrackId: nil
        )
        self.externalSubtitleTracks = [track1, track2]
        self.selectedExternalSubtitle = track2
        self.availableSubtitleTracks = [
            MediaTrack(id: 101, name: "PGS · ENG (pgssub)", language: "English", isDefault: false),
            MediaTrack(id: 102, name: "PGS · SDH", language: "English", isDefault: false),
            MediaTrack(id: 103, name: "PGS · ARA (pgssub)", language: "Arabic", isDefault: false),
            MediaTrack(id: 104, name: "PGS", language: "English", isDefault: false),
            MediaTrack(id: 105, name: "PGS ", language: "English", isDefault: false)
        ]
        self.subtitleStyle.backgroundOpacity = 0.0
        self.subtitleSyncSettings = SubtitleSyncSettings(
            manualOffset: 0.0,
            autoSyncEnabled: false,
            fixRTL: false,
            fixReversedPunctuation: false
        )
        self.currentSubtitleCue = AuraSubtitleCue(
            id: 1,
            startTime: 2340,
            endTime: 2358,
            text: "يا (007) أنا ضابط الإعاشة\nالجديد المكلف بكَ",
            processedText: nil,
            isArabic: true
        )
        self.syncStatusMessage = "Matches the video's English subtitle: offset, frame rate and cuts"
        self.showSubtitlePicker = (mode == .subtitlesMenu)
        self.showSubtitleSyncSheet = (mode == .subtitleSync)
    }

    // MARK: - Playback Controls

    func play() {
        isPlaying = true
        resetHUDTimer()
    }

    func pause() {
        isPlaying = false
        showHUD()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: Double) {
        let target = max(0, min(time, totalDuration))
        currentTime = target
        seekTrigger = target
        resetHUDTimer()
    }

    func seekForward(seconds: Double = 10) {
        seek(to: currentTime + seconds)
    }

    func seekBackward(seconds: Double = 10) {
        seek(to: currentTime - seconds)
    }

    func switchStream(_ stream: StremioStream) {
        guard let urlStr = stream.url, let url = URL(string: urlStr) else { return }
        playbackError = nil
        activeEmbeddedTextCue = nil
        currentBitmapSubtitle = nil
        externalASSContent = nil
        isActiveEmbeddedASS = false
        embeddedPlainCuesForSync = []
        translatedCueTexts = [:]
        inFlightTranslationIds = []
        translationTask?.cancel()
        translationTask = nil
        activeEmbeddedTrackLanguageCode = nil
        referenceEmbeddedCues = []
        subtitleRevision += 1
        isSyncingSubtitles = false
        selectedStream = stream
        resumeFromTime = currentTime
        introRange = nil
        streamURL = url
        isBuffering = true
        showStreamPicker = false
    }

    // MARK: - Skip Intro / Up Next

    func skipIntro() {
        guard let introRange, introRange.contains(currentTime) else { return }
        skipIntroDismissed = true
        didAutoSkipIntro = true
        seek(to: introRange.upperBound)
    }

    func dismissSkipIntro() {
        skipIntroDismissed = true
    }

    func skipCredits() {
        skipCreditsDismissed = true
        if nextEpisode != nil {
            Task { @MainActor in
                playNextEpisodeNow()
            }
        } else {
            seek(to: max(currentTime, totalDuration - 2))
        }
    }

    func dismissUpNext() {
        upNextDismissed = true
    }

    @MainActor
    func playNextEpisodeNow() {
        guard let nextEpisode else { return }
        upNextTriggered = true
        upNextDismissed = true
        saveProgress()
        onPlayNextEpisode?(nextEpisode)
    }

    // MARK: - Track Selection

    func selectAudioTrack(_ trackId: Int) {
        selectedAudioTrackId = trackId
    }

    func selectSubtitleTrack(_ trackId: Int) {
        selectedSubtitleTrackId = trackId
        translatedCueTexts = [:]
        inFlightTranslationIds = []
        translationTask?.cancel()
        translationTask = nil
        if trackId < 0 {
            activeEmbeddedTextCue = nil
            currentBitmapSubtitle = nil
            isActiveEmbeddedASS = false
            embeddedPlainCuesForSync = []
            activeEmbeddedTrackLanguageCode = nil
            if selectedExternalSubtitle == nil && !isPreviewMode {
                currentSubtitleCue = nil
            }
        }
    }

    @MainActor
    func updateEmbeddedSubtitle(
        text: String?,
        bitmap: CGImage?,
        cueId: Int? = nil,
        languageCode: String? = nil
    ) {
        activeEmbeddedTrackLanguageCode = languageCode?.lowercased()
        guard selectedExternalSubtitle == nil, selectedSubtitleTrackId >= 0 else {
            activeEmbeddedTextCue = nil
            currentBitmapSubtitle = nil
            return
        }

        currentBitmapSubtitle = bitmap

        if let text, !text.isEmpty, !isActiveEmbeddedASS {
            let isArabic = SubtitleProcessor.containsArabicCharacters(text)
            let cue = AuraSubtitleCue(
                id: cueId ?? (-selectedSubtitleTrackId - 1),
                startTime: currentTime,
                endTime: currentTime + 1.0,
                text: text,
                processedText: nil,
                isArabic: isArabic
            )
            activeEmbeddedTextCue = cue
            currentSubtitleCue = applyTranslationIfAvailable(to: cue)
            scheduleUpcomingTranslationIfNeeded(at: currentTime)
        } else {
            activeEmbeddedTextCue = nil
            if activeCues.isEmpty && !isPreviewMode {
                currentSubtitleCue = nil
            }
        }
    }

    @MainActor
    func applySyncToCue(_ cue: AuraSubtitleCue) {
        let computed = currentTime - cue.startTime
        let rounded = (computed * 100.0).rounded() / 100.0
        subtitleSyncSettings.manualOffset = rounded
        syncStatusMessage = "Synced to line (\(SubtitleSyncEngine.formatOffset(rounded)))"
        showSyncToLineSheet = false
        saveSubtitlePreferences()
        onTimeUpdate(current: currentTime, total: totalDuration)
    }

    @MainActor
    func appendReferenceEmbeddedCues(_ newCues: [AuraSubtitleCue]) {
        guard !newCues.isEmpty, referenceEmbeddedCues.count < 5000 else { return }
        var seenStarts = Set(referenceEmbeddedCues.map { Int(($0.startTime * 100.0).rounded()) })
        for cue in newCues where !cue.text.isEmpty {
            let bucket = Int((cue.startTime * 100.0).rounded())
            if seenStarts.insert(bucket).inserted {
                referenceEmbeddedCues.append(cue)
            }
        }
    }

    // MARK: - HUD Management

    func showHUD() {
        isHUDVisible = true
        resetHUDTimer()
    }

    func hideHUD() {
        guard !hasActiveModalOverlay && !isPreviewMode else { return }
        isHUDVisible = false
        showAudioPicker = false
        showSubtitlePicker = false
        showOptionsMenu = false
        showInfoPanel = false
    }

    func cycleAspectRatio() {
        let all = AspectRatioMode.allCases
        if let idx = all.firstIndex(of: aspectRatioMode) {
            aspectRatioMode = all[(idx + 1) % all.count]
        } else {
            aspectRatioMode = .fit
        }
        resetHUDTimer()
    }

    func cyclePlaybackSpeed() {
        let speeds = Self.speedOptions
        if let idx = speeds.firstIndex(where: { abs($0 - playbackRate) < 0.01 }) {
            playbackRate = speeds[(idx + 1) % speeds.count]
        } else {
            playbackRate = 1.0
        }
        resetHUDTimer()
    }

    func cycleSleepTimer() {
        let opts = Self.sleepTimerOptions
        let currentIdx = opts.firstIndex(of: sleepTimerOption) ?? 0
        let next = opts[(currentIdx + 1) % opts.count]
        setSleepTimer(option: next)
        resetHUDTimer()
    }

    private func setSleepTimer(option: Int) {
        sleepTimerCountdown?.invalidate()
        sleepTimerCountdown = nil
        sleepTimerOption = option

        guard option > 0 else {
            sleepTimerRemainingSeconds = nil
            return
        }

        sleepTimerRemainingSeconds = option * 60
        sleepTimerCountdown = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let rem = self.sleepTimerRemainingSeconds else { return }
                if rem <= 1 {
                    self.sleepTimerCountdown?.invalidate()
                    self.sleepTimerCountdown = nil
                    self.sleepTimerRemainingSeconds = nil
                    self.sleepTimerOption = 0
                    self.pause()
                } else {
                    self.sleepTimerRemainingSeconds = rem - 1
                }
            }
        }
    }

    func toggleHUD() {
        if isHUDVisible {
            hideHUD()
        } else {
            showHUD()
        }
    }

    private func resetHUDTimer() {
        hudHideTimer?.invalidate()
        guard !isPreviewMode else { return }
        hudHideTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying, !self.hasActiveModalOverlay else { return }
                self.hideHUD()
            }
        }
    }

    // MARK: - Buffering

    func onBufferingStarted() {
        isBuffering = true
    }

    func onBufferingEnded() {
        isBuffering = false
    }

    func onPlaybackReady(duration: Double) {
        if duration.isFinite && duration < Double(Int.max) && duration > 0 {
            totalDuration = duration
        }
        isBuffering = false

        if resumeFromTime > 0 {
            seek(to: resumeFromTime)
            resumeFromTime = 0
        }

        play()
    }

    // MARK: - Time Updates

    @MainActor
    func onTimeUpdate(current: Double, total: Double) {
        guard current.isFinite, current >= 0, current < Double(Int.max) else { return }
        currentTime = current
        if total.isFinite && total < Double(Int.max) && total > 0 { totalDuration = total }

        // Update active subtitle cue based on current time & manual offset
        if !activeCues.isEmpty {
            let offset = subtitleSyncSettings.manualOffset
            if let matchingCue = activeCues.first(where: { $0.isActive(at: current, offset: offset) }) {
                currentSubtitleCue = externalASSContent == nil ? applyTranslationIfAvailable(to: matchingCue) : nil
            } else {
                currentSubtitleCue = nil
            }
            scheduleUpcomingTranslationIfNeeded(at: current)
        } else if let embeddedCue = activeEmbeddedTextCue {
            currentSubtitleCue = isActiveEmbeddedASS ? nil : applyTranslationIfAvailable(to: embeddedCue)
            scheduleUpcomingTranslationIfNeeded(at: current)
        } else if !isPreviewMode {
            currentSubtitleCue = nil
            scheduleUpcomingTranslationIfNeeded(at: current)
        }

        // Auto-skip intro if configured in Settings
        if skipIntroMode == "Skip After Delay",
           !didAutoSkipIntro,
           let remaining = skipIntroCountdownRemaining,
           remaining == 0 {
            skipIntro()
        }

        // Auto-advance to next episode if Up Next countdown reaches 0 (unless Sleep Timer is set to End of Episode)
        if showUpNextOverlay,
           !upNextTriggered,
           sleepTimerOption != -1,
           upNextCountdownRemaining == 0,
           (totalDuration - currentTime) <= 2 {
            playNextEpisodeNow()
        }
    }

    // MARK: - Subtitle Operations

    @MainActor
    func fetchSubtitles() async {
        isFetchingSubtitles = true
        defer { isFetchingSubtitles = false }
        guard imdbId.hasPrefix("tt") else { return }
        let revision = subtitleRevision
        let queryId = imdbId

        let externalTracks = await SubtitleService.shared.fetchSubtitles(
            imdbId: queryId,
            season: seasonNumber,
            episode: episodeNumber,
            preferredLanguage: preferredSubtitleLanguage
        )

        externalSubtitleTracks = externalTracks

        if revision == subtitleRevision, selectedExternalSubtitle == nil {
            if let preferredTrack = externalTracks.first(where: { $0.languageCode.lowercased() == preferredSubtitleLanguage.lowercased() })
                ?? externalTracks.first(where: { $0.languageCode == "ar" }) {
                await selectExternalSubtitleTrack(preferredTrack)
            }
        }

    }

    @MainActor
    func selectExternalSubtitleTrack(_ track: SubtitleTrackItem?) async {
        subtitleRevision += 1
        let revision = subtitleRevision
        activeCues = []
        isSyncingSubtitles = false
        selectedExternalSubtitle = track
        externalASSContent = nil
        translatedCueTexts = [:]
        inFlightTranslationIds = []
        translationTask?.cancel()
        translationTask = nil

        guard let track else {
            activeCues = []
            if !isPreviewMode && activeEmbeddedTextCue == nil { currentSubtitleCue = nil }
            selectedSubtitleTrackId = -1
            return
        }

        selectedSubtitleTrackId = -1
        activeEmbeddedTextCue = nil
        currentBitmapSubtitle = nil
        isActiveEmbeddedASS = false

        do {
            let loaded = try await SubtitleService.shared.loadSubtitleTrack(for: track)
            guard revision == subtitleRevision else { return }
            self.activeCues = loaded.cues
            self.externalASSContent = loaded.rawASSContent

            if loaded.rawASSContent != nil {
                self.currentSubtitleCue = nil
                self.syncStatusMessage = "\(loaded.cues.count) ASS cues loaded (\(track.source.badgeName))"
            } else {
                self.syncStatusMessage = "\(loaded.cues.count) cues loaded (\(track.source.badgeName))"
            }

            if subtitleSyncSettings.autoSyncEnabled {
                await performSyncNow()
            }

            onTimeUpdate(current: currentTime, total: totalDuration)
        } catch {
            guard revision == subtitleRevision else { return }
            self.activeCues = []
            self.externalASSContent = nil
            self.syncStatusMessage = "Could not load subtitle track."
        }
    }

    // MARK: - AI Live Subtitle Translation

    private func applyTranslationIfAvailable(to cue: AuraSubtitleCue) -> AuraSubtitleCue {
        guard aiTranslationConfig.isConfigured,
              !isASSTrackActive,
              let translated = translatedCueTexts[cue.id],
              !translated.isEmpty else {
            return cue
        }
        var updated = cue
        updated.text = translated
        updated.isArabic = SubtitleProcessor.containsArabicCharacters(translated)
        return updated
    }

    private func shouldTranslateCurrentTrack(trackLanguageCode: String?) -> Bool {
        guard !isPreviewMode,
              aiTranslationConfig.isConfigured,
              !isASSTrackActive,
              currentBitmapSubtitle == nil else {
            return false
        }

        let targetCode = aiTranslationConfig.targetLanguageCode.lowercased()
        if let lang = trackLanguageCode?.lowercased(), !lang.isEmpty {
            if lang == targetCode || lang.hasPrefix(targetCode) {
                return false
            }
        }
        return true
    }

    @MainActor
    private func scheduleUpcomingTranslationIfNeeded(at playbackTime: Double) {
        let trackLang = selectedExternalSubtitle?.languageCode ?? activeEmbeddedTrackLanguageCode
        guard shouldTranslateCurrentTrack(trackLanguageCode: trackLang) else { return }

        let candidates: [AuraSubtitleCue]
        let trackCacheKey: String
        if !activeCues.isEmpty && externalASSContent == nil {
            candidates = activeCues
            trackCacheKey = "ext|\(selectedExternalSubtitle?.id ?? "unknown")"
        } else if !isActiveEmbeddedASS && !embeddedPlainCuesForSync.isEmpty {
            candidates = embeddedPlainCuesForSync
            trackCacheKey = "emb|\(streamURL?.absoluteString ?? "\(tmdbId)")|\(selectedSubtitleTrackId)"
        } else {
            return
        }

        let offset = subtitleSyncSettings.manualOffset
        let adjustedNow = playbackTime - offset
        let windowEnd = adjustedNow + 45.0

        let batch = candidates.filter { cue in
            cue.endTime >= (adjustedNow - 1.5) &&
            cue.startTime <= windowEnd &&
            translatedCueTexts[cue.id] == nil &&
            !inFlightTranslationIds.contains(cue.id) &&
            !(aiTranslationConfig.targetLanguageCode.lowercased() == "ar" && cue.isArabic)
        }
        .prefix(12)

        guard !batch.isEmpty else { return }
        let batchArray = Array(batch)
        for cue in batchArray {
            inFlightTranslationIds.insert(cue.id)
        }

        let config = aiTranslationConfig
        translationTask = Task { @MainActor [weak self] in
            let results = await AITranslationService.shared.translateBatch(
                cues: batchArray,
                trackKey: trackCacheKey,
                config: config
            )
            guard let self else { return }
            for cue in batchArray {
                self.inFlightTranslationIds.remove(cue.id)
            }
            guard !Task.isCancelled, !results.isEmpty else { return }
            for (id, translated) in results {
                self.translatedCueTexts[id] = translated
            }

            // Immediately update visible subtitle if the current cue just got translated.
            if let current = self.currentSubtitleCue, let freshText = results[current.id] {
                var refreshed = current
                refreshed.text = freshText
                refreshed.isArabic = SubtitleProcessor.containsArabicCharacters(freshText)
                self.currentSubtitleCue = refreshed
            } else if !self.activeCues.isEmpty {
                let offset = self.subtitleSyncSettings.manualOffset
                if let match = self.activeCues.first(where: { $0.isActive(at: self.currentTime, offset: offset) }) {
                    self.currentSubtitleCue = self.applyTranslationIfAvailable(to: match)
                }
            }
        }
    }

    @MainActor
    func performSyncNow() async {
        let revision = subtitleRevision
        isSyncingSubtitles = true
        syncStatusMessage = "Analyzing timing offset..."
        defer { if revision == subtitleRevision { isSyncingSubtitles = false } }

        guard !activeCues.isEmpty else {
            syncStatusMessage = isPreviewMode
                ? "Aligned preview offset (\(SubtitleSyncEngine.formatOffset(subtitleSyncSettings.manualOffset)))"
                : "Select an external subtitle track first."
            return
        }

        if referenceEmbeddedCues.isEmpty {
            if let englishTrack = externalSubtitleTracks.first(where: { $0.languageCode == "en" && $0.id != selectedExternalSubtitle?.id }) {
                if let refCues = try? await SubtitleService.shared.loadAndParseCues(for: englishTrack) {
                    guard revision == subtitleRevision else { return }
                    self.referenceEmbeddedCues = refCues
                }
            }
        }

        guard revision == subtitleRevision else { return }
        guard !referenceEmbeddedCues.isEmpty else {
            syncStatusMessage = "No English reference track found for auto-alignment."
            return
        }

        if let offset = SubtitleSyncEngine.calculateAutoSyncOffset(
            targetCues: activeCues,
            referenceCues: referenceEmbeddedCues
        ) {
            subtitleSyncSettings.manualOffset = offset
            syncStatusMessage = "Auto-aligned by \(SubtitleSyncEngine.formatOffset(offset))"
            saveSubtitlePreferences()
            onTimeUpdate(current: currentTime, total: totalDuration)
        } else {
            syncStatusMessage = "Could not correlate timestamps automatically."
        }
    }

    func loadSubtitleSettingsFromPreferences(context: ModelContext) {
        self.saveContext = context
        guard !isPreviewMode else { return }
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? context.fetch(descriptor).first {
            subtitleStyle.fontSize = settings.subtitleFontSize
            subtitleStyle.fontWeight = settings.subtitleFontWeight
            subtitleStyle.fontName = settings.subtitleFontName
            subtitleStyle.textColor = settings.subtitleTextColor
            subtitleStyle.backgroundOpacity = settings.subtitleBackgroundOpacity
            subtitleStyle.bottomOffset = settings.subtitleBottomOffset

            subtitleSyncSettings.fixRTL = settings.fixArabicRTL
            subtitleSyncSettings.fixReversedPunctuation = settings.fixReversedPunctuation
            subtitleSyncSettings.autoSyncEnabled = settings.autoSyncSubtitles

            preferredSubtitleLanguage = settings.subtitleLanguage
            preferredQuality = settings.preferredQuality
            skipIntroMode = settings.skipIntroMode
            skipRecapMode = settings.skipRecapMode
            skipCreditsMode = settings.skipCreditsMode
            skipDelaySeconds = settings.skipDelaySeconds
            nextEpisodeBehavior = settings.nextEpisodeBehavior
            playerEngineName = SettingsViewModel.playerEngineOptions.contains(settings.playerEngineName)
                ? settings.playerEngineName
                : "AetherEngine"
            audioOutputMode = settings.audioOutputMode
            dolbyVisionEnabled = settings.dolbyVisionEnabled
            dolbyVisionP7ToHDR10Fallback = settings.dolbyVisionP7ToHDR10Fallback
            hdrEnabled = settings.hdrEnabled
            matchContentFrameRate = settings.matchContentFrameRate
            losslessMultichannelAudio = settings.losslessMultichannelAudio
            objectAudioEnabled = settings.objectAudioEnabled
            seekCacheEnabled = settings.seekCacheEnabled
            bufferAheadMode = SettingsViewModel.bufferAheadOptions.contains(settings.bufferAheadMode) ? settings.bufferAheadMode : "Standard"
            audioSyncOffsetMs = max(-2000, min(2000, settings.audioSyncOffsetMs))
            playbackStats.activeEngine = playerEngineName

            SubtitleService.shared.subdlApiKey = settings.subdlApiKey
            SubtitleService.shared.openSubtitlesApiKey = settings.openSubtitlesApiKey

            let targetCode = settings.aiTranslationTargetLanguage.isEmpty ? "ar" : settings.aiTranslationTargetLanguage
            let targetName = SettingsViewModel.languageOptions.first(where: { $0.code == targetCode })?.name ?? targetCode.uppercased()
            aiTranslationConfig = SubtitleTranslationConfig(
                enabled: settings.aiTranslationEnabled,
                provider: settings.aiTranslationProvider,
                apiKey: settings.aiTranslationApiKey,
                targetLanguageCode: targetCode,
                targetLanguageName: targetName,
                customEndpoint: settings.aiTranslationCustomEndpoint,
                modelOverride: settings.aiTranslationModel
            )
        }
    }

    @MainActor
    func saveSubtitlePreferences() {
        guard let context = saveContext else { return }
        let descriptor = FetchDescriptor<AppSettings>()
        let settings: AppSettings
        if let existing = try? context.fetch(descriptor).first {
            settings = existing
        } else {
            settings = AppSettings()
            context.insert(settings)
        }

        settings.subtitleFontSize = subtitleStyle.fontSize
        settings.subtitleFontWeight = subtitleStyle.fontWeight
        settings.subtitleFontName = subtitleStyle.fontName
        settings.subtitleTextColor = subtitleStyle.textColor
        settings.subtitleBackgroundOpacity = subtitleStyle.backgroundOpacity
        settings.subtitleBottomOffset = subtitleStyle.bottomOffset

        settings.fixArabicRTL = subtitleSyncSettings.fixRTL
        settings.fixReversedPunctuation = subtitleSyncSettings.fixReversedPunctuation
        settings.autoSyncSubtitles = subtitleSyncSettings.autoSyncEnabled

        try? context.save()
    }

    // MARK: - Progress Saving

    func startPeriodicSave(context: ModelContext) {
        self.saveContext = context
        progressSaveTimer?.invalidate()
        guard !isPreviewMode else { return }
        progressSaveTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.saveProgress()
            }
        }
    }

    func stopPeriodicSave() {
        progressSaveTimer?.invalidate()
        progressSaveTimer = nil
    }

    @MainActor
    func saveProgress() {
        guard !isPreviewMode, let context = saveContext, totalDuration > 0 else { return }

        let tmdbIdVal = tmdbId
        let mediaTypeVal = mediaType
        let descriptor = FetchDescriptor<WatchHistory>(
            predicate: #Predicate<WatchHistory> { item in
                item.tmdbId == tmdbIdVal && item.mediaType == mediaTypeVal
            }
        )

        do {
            let existing = try context.fetch(descriptor)
            let history: WatchHistory

            if let found = existing.first {
                history = found
            } else {
                history = WatchHistory(
                    tmdbId: tmdbId,
                    mediaType: mediaType,
                    title: title,
                    posterPath: posterPath,
                    backdropPath: backdropPath
                )
                context.insert(history)
            }

            history.currentTime = currentTime
            history.totalDuration = totalDuration
            history.lastWatched = Date()
            history.seasonNumber = seasonNumber
            history.episodeNumber = episodeNumber
            history.episodeTitle = episodeTitle
            history.episodeStillPath = episodeStillPath

            if totalDuration > 0 {
                let completed = (currentTime / totalDuration) >= 0.95
                history.isCompleted = completed
                if mediaType == "series",
                   (currentTime / totalDuration) >= 0.90,
                   let seasonNumber,
                   let episodeNumber {
                    EpisodeWatchedStore.markWatched(
                        tmdbId: tmdbId,
                        season: seasonNumber,
                        episode: episodeNumber,
                        watched: true
                    )
                }
            }

            try context.save()
        } catch {
            // Silent fail for periodic saves
        }
    }

    // MARK: - Cleanup

    @MainActor
    func cleanup() {
        translationTask?.cancel()
        translationTask = nil
        hudHideTimer?.invalidate()
        hudHideTimer = nil
        sleepTimerCountdown?.invalidate()
        sleepTimerCountdown = nil
        stopPeriodicSave()
        saveProgress()
    }

    // MARK: - Time Formatting

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(max(seconds, 0))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}
