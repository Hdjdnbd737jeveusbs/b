import Foundation
import SwiftData
import Observation
#if canImport(KSPlayer)
import KSPlayer
#endif

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

    // MARK: - Track Selection

    var availableAudioTracks: [MediaTrack] = []
    var availableSubtitleTracks: [MediaTrack] = []
    var selectedAudioTrackId: Int = 0
    var selectedSubtitleTrackId: Int = -1 // -1 = off

    // MARK: - Phase 3: Subtitles, Styling & Sync State

    var externalSubtitleTracks: [SubtitleTrackItem] = []
    var selectedExternalSubtitle: SubtitleTrackItem?
    var activeCues: [SubtitleCue] = []
    var currentSubtitleCue: SubtitleCue?
    var referenceEmbeddedCues: [SubtitleCue] = []
    var subtitleSyncSettings: SubtitleSyncSettings = .defaultSettings
    var subtitleStyle: SubtitleStyle = .defaultStyle
    var isFetchingSubtitles: Bool = false
    var showSubtitleStyleSheet: Bool = false
    var showSubtitleSyncSheet: Bool = false
    var subtitleSearchText: String = ""
    var imdbId: String = ""

    // Filtered external subtitle tracks based on search
    var filteredSubtitleTracks: [SubtitleTrackItem] {
        if subtitleSearchText.isEmpty {
            return externalSubtitleTracks
        } else {
            return externalSubtitleTracks.filter {
                $0.name.localizedCaseInsensitiveContains(subtitleSearchText) ||
                $0.language.localizedCaseInsensitiveContains(subtitleSearchText) ||
                ($0.releaseInfo?.localizedCaseInsensitiveContains(subtitleSearchText) ?? false)
            }
        }
    }

    // MARK: - HUD State

    var isHUDVisible: Bool = true
    var showAudioPicker: Bool = false
    var showSubtitlePicker: Bool = false
    var showInfoPanel: Bool = false

    // MARK: - Media Info

    var title: String = ""
    var backdropPath: String?
    var tmdbId: Int = 0
    var mediaType: String = "movie"
    var seasonNumber: Int?
    var episodeNumber: Int?
    var episodeTitle: String?
    var episodeStillPath: String?
    var posterPath: String?

    // MARK: - Resume

    var resumeFromTime: Double = 0

    // MARK: - Timers

    private var hudHideTimer: Timer?
    private var progressSaveTimer: Timer?
    private var saveContext: ModelContext?

    // MARK: - Computed Properties

    /// Progress between 0 and 1.
    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return min(max(currentTime / totalDuration, 0), 1)
    }

    /// Current time formatted as "39:10" or "1:23:45".
    var currentTimeFormatted: String {
        formatTime(currentTime)
    }

    /// Remaining time formatted as "-1:43:59".
    var remainingTimeFormatted: String {
        let remaining = max(totalDuration - currentTime, 0)
        return "-\(formatTime(remaining))"
    }

    /// Whether the stream has started playing (past buffering).
    var hasStartedPlayback: Bool {
        !isBuffering && totalDuration > 0
    }

    // MARK: - Setup

    /// Configure the player with media info and prepare for playback.
    func configure(
        url: URL,
        title: String,
        backdropPath: String?,
        posterPath: String?,
        tmdbId: Int,
        mediaType: String,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil,
        episodeStillPath: String? = nil,
        resumeFrom: Double = 0,
        imdbId: String = ""
    ) {
        self.streamURL = url
        self.title = title
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
        self.isBuffering = true
        self.isPlaying = false
        self.currentTime = resumeFrom

        // Auto-fetch external subtitles for this title
        Task {
            await fetchSubtitles()
        }
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
        currentTime = max(0, min(time, totalDuration))
        resetHUDTimer()
    }

    func seekForward(seconds: Double = 10) {
        seek(to: currentTime + seconds)
    }

    func seekBackward(seconds: Double = 10) {
        seek(to: currentTime - seconds)
    }

    // MARK: - Track Selection

    func selectAudioTrack(_ trackId: Int) {
        selectedAudioTrackId = trackId
    }

    func selectSubtitleTrack(_ trackId: Int) {
        selectedSubtitleTrackId = trackId
    }

    // MARK: - HUD Management

    func showHUD() {
        isHUDVisible = true
        resetHUDTimer()
    }

    func hideHUD() {
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
        hudHideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
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
        totalDuration = duration
        isBuffering = false

        // Auto-seek to resume point
        if resumeFromTime > 0 {
            seek(to: resumeFromTime)
            resumeFromTime = 0
        }

        play()
    }

    // MARK: - Time Updates

    func onTimeUpdate(current: Double, total: Double) {
        currentTime = current
        if total > 0 { totalDuration = total }

        // Update active subtitle cue based on current time & manual offset
        if !activeCues.isEmpty {
            let offset = subtitleSyncSettings.manualOffset
            currentSubtitleCue = activeCues.first { cue in
                cue.isActive(at: current, offset: offset)
            }
        } else {
            currentSubtitleCue = nil
        }
    }

    // MARK: - Phase 3: Subtitle Operations

    @MainActor
    func fetchSubtitles() async {
        isFetchingSubtitles = true
        let queryId = imdbId.isEmpty ? "\(tmdbId)" : imdbId

        // Fetch external subtitles across Wyzie, SubDL, and OpenSubtitles
        let externalTracks = await SubtitleService.shared.fetchSubtitles(
            imdbId: queryId,
            season: seasonNumber,
            episode: episodeNumber,
            preferredLanguage: "ar"
        )

        externalSubtitleTracks = externalTracks

        // Auto-select first Arabic track if available, or first track
        if selectedExternalSubtitle == nil {
            if let firstArabic = externalTracks.first(where: { $0.languageCode == "ar" }) {
                await selectExternalSubtitleTrack(firstArabic)
            }
        }

        isFetchingSubtitles = false
    }

    @MainActor
    func selectExternalSubtitleTrack(_ track: SubtitleTrackItem?) async {
        selectedExternalSubtitle = track

        guard let track else {
            activeCues = []
            currentSubtitleCue = nil
            selectedSubtitleTrackId = -1
            return
        }

        do {
            let cues = try await SubtitleService.shared.loadAndParseCues(for: track)
            self.activeCues = cues

            // If auto-sync is enabled and reference cues exist, auto-align
            if subtitleSyncSettings.autoSyncEnabled {
                await performSyncNow()
            }
        } catch {
            self.activeCues = []
        }
    }

    @MainActor
    func performSyncNow() async {
        guard !activeCues.isEmpty else { return }

        // Fallback: If embedded cues are not available, fetch the primary English track as reference
        if referenceEmbeddedCues.isEmpty {
            if let englishTrack = externalSubtitleTracks.first(where: { $0.languageCode == "en" && $0.id != selectedExternalSubtitle?.id }) {
                if let refCues = try? await SubtitleService.shared.loadAndParseCues(for: englishTrack) {
                    self.referenceEmbeddedCues = refCues
                }
            }
        }

        guard !referenceEmbeddedCues.isEmpty else { return }

        if let offset = SubtitleSyncEngine.calculateAutoSyncOffset(
            targetCues: activeCues,
            referenceCues: referenceEmbeddedCues
        ) {
            subtitleSyncSettings.manualOffset = offset
        }
    }

    func loadSubtitleSettingsFromPreferences(context: ModelContext) {
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

            SubtitleService.shared.subdlApiKey = settings.subdlApiKey
            SubtitleService.shared.openSubtitlesApiKey = settings.openSubtitlesApiKey
        }
    }

    // MARK: - Progress Saving

    func startPeriodicSave(context: ModelContext) {
        self.saveContext = context
        progressSaveTimer?.invalidate()
        progressSaveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
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
        guard let context = saveContext, totalDuration > 0 else { return }

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
