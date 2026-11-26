import Foundation
import SwiftData
import Observation
import CoreGraphics

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
    var playbackError: String?
    var videoDynamicRangeBadge: String?

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
    private var subtitleSelectionRevision = 0
    var selectedExternalSubtitle: SubtitleTrackItem?
    var activeCues: [AuraSubtitleCue] = []
    var currentSubtitleCue: AuraSubtitleCue?
    var activeEmbeddedTextCue: AuraSubtitleCue?
    var currentBitmapSubtitle: CGImage?
    var referenceEmbeddedCues: [AuraSubtitleCue] = []
    var subtitleSyncSettings: SubtitleSyncSettings = .defaultSettings
    var subtitleStyle: SubtitleStyle = .defaultStyle
    var isFetchingSubtitles: Bool = false
    var isSyncingSubtitles: Bool = false
    var syncStatusMessage: String?
    var showSubtitleStyleSheet: Bool = false
    var showSubtitleSyncSheet: Bool = false
    var subtitleSearchText: String = ""
    var imdbId: String = ""
    var preferredSubtitleLanguage: String = "ar"

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
    var showInfoPanel: Bool = false

    var hasActiveModalOverlay: Bool {
        showAudioPicker || showSubtitlePicker || showInfoPanel || showSubtitleSyncSheet || showSubtitleStyleSheet || showStreamPicker
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

    var showSkipIntroPill: Bool {
        mediaType == "series"
            && !skipIntroDismissed
            && skipIntroMode != "Off"
            && totalDuration > 180
            && currentTime >= 15
            && currentTime <= 105
    }

    var skipIntroCountdownRemaining: Int? {
        guard showSkipIntroPill, skipIntroMode == "Skip After Delay" else { return nil }
        return max(0, skipDelaySeconds - Int(currentTime - 15))
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
            && (totalDuration - currentTime) <= 45
    }

    var upNextCountdownRemaining: Int {
        let configured = nextEpisodeBehavior.contains("5") ? 5 : 10
        let remainingUntilEnd = max(0, Int(totalDuration - currentTime))
        return min(configured, max(0, remainingUntilEnd - (45 - configured)))
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
        selectedStream = stream
        resumeFromTime = currentTime
        streamURL = url
        isBuffering = true
        showStreamPicker = false
    }

    // MARK: - Skip Intro / Up Next

    func skipIntro() {
        skipIntroDismissed = true
        didAutoSkipIntro = true
        let target = min(105, max(currentTime, totalDuration - 10))
        seek(to: target)
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
        if trackId < 0 {
            activeEmbeddedTextCue = nil
            currentBitmapSubtitle = nil
            if selectedExternalSubtitle == nil && !isPreviewMode {
                currentSubtitleCue = nil
            }
        }
    }

    @MainActor
    func updateEmbeddedSubtitle(text: String?, bitmap: CGImage?) {
        guard selectedExternalSubtitle == nil, selectedSubtitleTrackId >= 0 else {
            activeEmbeddedTextCue = nil
            currentBitmapSubtitle = nil
            return
        }

        currentBitmapSubtitle = bitmap

        if let text, !text.isEmpty {
            let isArabic = text.unicodeScalars.contains { scalar in
                (0x0600...0x06FF).contains(scalar.value) ||
                (0x0750...0x077F).contains(scalar.value) ||
                (0x08A0...0x08FF).contains(scalar.value) ||
                (0xFB50...0xFDFF).contains(scalar.value) ||
                (0xFE70...0xFEFF).contains(scalar.value)
            }
            let cue = AuraSubtitleCue(
                id: -selectedSubtitleTrackId - 1,
                startTime: currentTime,
                endTime: currentTime + 1.0,
                text: text,
                processedText: nil,
                isArabic: isArabic
            )
            activeEmbeddedTextCue = cue
            currentSubtitleCue = cue
        } else {
            activeEmbeddedTextCue = nil
            if activeCues.isEmpty && !isPreviewMode {
                currentSubtitleCue = nil
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
        showInfoPanel = false
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
        if duration > 0 {
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
        currentTime = current
        if total > 0 { totalDuration = total }

        // Update active subtitle cue based on current time & manual offset
        if !activeCues.isEmpty {
            let offset = subtitleSyncSettings.manualOffset
            currentSubtitleCue = activeCues.first { cue in
                cue.isActive(at: current, offset: offset)
            }
        } else if let embeddedCue = activeEmbeddedTextCue {
            currentSubtitleCue = embeddedCue
        } else if !isPreviewMode {
            currentSubtitleCue = nil
        }

        // Auto-skip intro if configured in Settings
        if skipIntroMode == "Skip After Delay",
           !didAutoSkipIntro,
           let remaining = skipIntroCountdownRemaining,
           remaining == 0 {
            skipIntro()
        }

        // Auto-advance to next episode if Up Next countdown reaches 0
        if showUpNextOverlay,
           !upNextTriggered,
           upNextCountdownRemaining == 0,
           (totalDuration - currentTime) <= 2 {
            playNextEpisodeNow()
        }
    }

    // MARK: - Subtitle Operations

    @MainActor
    func fetchSubtitles() async {
        isFetchingSubtitles = true
        let queryId = imdbId.isEmpty ? "\(tmdbId)" : imdbId

        let externalTracks = await SubtitleService.shared.fetchSubtitles(
            imdbId: queryId,
            season: seasonNumber,
            episode: episodeNumber,
            preferredLanguage: preferredSubtitleLanguage
        )

        externalSubtitleTracks = externalTracks

        if selectedExternalSubtitle == nil {
            if let preferredTrack = externalTracks.first(where: { $0.languageCode.lowercased() == preferredSubtitleLanguage.lowercased() })
                ?? externalTracks.first(where: { $0.languageCode == "ar" }) {
                await selectExternalSubtitleTrack(preferredTrack)
            }
        }

        isFetchingSubtitles = false
    }

    @MainActor
    func selectExternalSubtitleTrack(_ track: SubtitleTrackItem?) async {
        subtitleSelectionRevision += 1
        let revision = subtitleSelectionRevision
        selectedExternalSubtitle = track
        isSyncingSubtitles = false
        activeCues = []
        if !isPreviewMode { currentSubtitleCue = nil }

        guard let track else {
            if !isPreviewMode && activeEmbeddedTextCue == nil { currentSubtitleCue = nil }
            selectedSubtitleTrackId = -1
            return
        }

        selectedSubtitleTrackId = -1
        activeEmbeddedTextCue = nil
        currentBitmapSubtitle = nil

        do {
            let cues = try await SubtitleService.shared.loadAndParseCues(for: track)
            guard revision == subtitleSelectionRevision else { return }
            self.activeCues = cues
            self.syncStatusMessage = "\(cues.count) cues loaded (\(track.source.badgeName))"

            if subtitleSyncSettings.autoSyncEnabled {
                await performSyncNow()
            }
        } catch {
            guard revision == subtitleSelectionRevision else { return }
            self.activeCues = []
            self.syncStatusMessage = "Could not load subtitle track."
        }
    }

    @MainActor
    func performSyncNow() async {
        let revision = subtitleSelectionRevision
        isSyncingSubtitles = true
        syncStatusMessage = "Analyzing timing offset..."
        defer {
            if revision == subtitleSelectionRevision { isSyncingSubtitles = false }
        }

        guard !activeCues.isEmpty else {
            syncStatusMessage = isPreviewMode
                ? "Aligned preview offset (\(SubtitleSyncEngine.formatOffset(subtitleSyncSettings.manualOffset)))"
                : "Select an external subtitle track first."
            return
        }

        if referenceEmbeddedCues.isEmpty {
            if let englishTrack = externalSubtitleTracks.first(where: { $0.languageCode == "en" && $0.id != selectedExternalSubtitle?.id }) {
                if let refCues = try? await SubtitleService.shared.loadAndParseCues(for: englishTrack) {
                    guard revision == subtitleSelectionRevision else { return }
                    self.referenceEmbeddedCues = refCues
                }
            }
        }

        guard revision == subtitleSelectionRevision else { return }
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

            SubtitleService.shared.subdlApiKey = settings.subdlApiKey
            SubtitleService.shared.openSubtitlesApiKey = settings.openSubtitlesApiKey
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
                history.isCompleted = (currentTime / totalDuration) >= 0.95
            }

            try context.save()
        } catch {
            // Silent fail for periodic saves
        }
    }

    // MARK: - Cleanup

    @MainActor
    func cleanup() {
        hudHideTimer?.invalidate()
        hudHideTimer = nil
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
