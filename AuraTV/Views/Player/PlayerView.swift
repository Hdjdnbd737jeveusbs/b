import SwiftUI
import SwiftData
import AVKit
import AVFoundation
import Combine
#if canImport(AetherEngine)
import AetherEngine
#endif

// MARK: - Player View

struct PlayerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: PlayerViewModel
    @State private var didResolveEnginePreference: Bool = false

    #if canImport(AetherEngine)
    @StateObject private var aetherCoordinator = AetherPlayerCoordinator()
    #endif

    // MARK: - Init

    init(viewModel: PlayerViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            Color.auraBackground.ignoresSafeArea()

            // Video Player Layer (or backdrop frame when in CI Preview Mode)
            if viewModel.isPreviewMode {
                previewBackdropLayer
            } else {
                videoPlayerLayer
            }

            // Live Subtitle Overlay Layer (shifted above scrubber when HUD is visible)
            SubtitleOverlayView(
                currentCue: viewModel.currentSubtitleCue,
                bitmapCue: viewModel.currentBitmapSubtitle,
                style: viewModel.subtitleStyle,
                fixRTL: viewModel.subtitleSyncSettings.fixRTL,
                fixReversedPunctuation: viewModel.subtitleSyncSettings.fixReversedPunctuation,
                isHUDVisible: viewModel.hasStartedPlayback && viewModel.isHUDVisible && !viewModel.showSubtitleSyncSheet && !viewModel.showSubtitleStyleSheet
            )

            // Loading Overlay (shown while buffering & no playback yet)
            if viewModel.isBuffering && !viewModel.hasStartedPlayback {
                LoadingOverlayView(
                    title: viewModel.title,
                    backdropPath: viewModel.backdropPath,
                    tmdbId: viewModel.tmdbId,
                    mediaType: viewModel.mediaType
                )
                .transition(.opacity)
            }

            // Player HUD (Title top-left, 5 icons + scrubber bottom; hidden while Sync/Style popovers are open)
            if viewModel.hasStartedPlayback && !viewModel.showSubtitleSyncSheet && !viewModel.showSubtitleStyleSheet {
                PlayerHUDView(viewModel: viewModel)
                    .opacity(viewModel.isHUDVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.isHUDVisible)
            }

            // Live Subtitle Sync Popover (Right-Anchored, no full-screen dark dimmer)
            if viewModel.showSubtitleSyncSheet {
                SubtitleSyncSheet(
                    settings: $viewModel.subtitleSyncSettings,
                    isSyncing: viewModel.isSyncingSubtitles,
                    statusMessage: viewModel.syncStatusMessage,
                    onSyncNow: {
                        Task {
                            await viewModel.performSyncNow()
                        }
                    },
                    onDismiss: {
                        viewModel.saveSubtitlePreferences()
                        viewModel.showSubtitleSyncSheet = false
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Live Subtitle Styling Overlay (Right-Anchored, no full-screen dark dimmer)
            if viewModel.showSubtitleStyleSheet {
                SubtitleStyleSheet(
                    style: $viewModel.subtitleStyle,
                    onDismiss: {
                        viewModel.saveSubtitlePreferences()
                        viewModel.showSubtitleStyleSheet = false
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Buffering indicator during active playback
            if viewModel.isBuffering && viewModel.hasStartedPlayback && !viewModel.isPreviewMode && viewModel.playbackError == nil {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }

            // Playback failure overlay with AVPlayer fallback switch
            if let errorMessage = viewModel.playbackError, !viewModel.isPreviewMode {
                playbackErrorOverlay(message: errorMessage)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            viewModel.loadSubtitleSettingsFromPreferences(context: modelContext)
            viewModel.startPeriodicSave(context: modelContext)
            didResolveEnginePreference = true
        }
        .task(id: viewModel.streamURL) {
            if !viewModel.isPreviewMode, let url = viewModel.streamURL {
                viewModel.loadSubtitleSettingsFromPreferences(context: modelContext)
                await viewModel.loadIntroMarker(for: url)
            }
        }
        .onChange(of: viewModel.subtitleSyncSettings) { _, _ in
            viewModel.saveSubtitlePreferences()
            #if canImport(AetherEngine)
            aetherCoordinator.refreshEmbeddedSubtitleCue()
            #endif
        }
        .onChange(of: viewModel.subtitleStyle) { _, _ in
            viewModel.saveSubtitlePreferences()
        }
        .sheet(isPresented: $viewModel.showStreamPicker) {
            StreamPickerSheet(
                title: viewModel.title,
                streams: viewModel.availableStreams,
                selectedStream: viewModel.selectedStream,
                preferredQuality: viewModel.preferredQuality,
                onSelect: { stream in
                    viewModel.switchStream(stream)
                },
                onDismiss: { viewModel.showStreamPicker = false }
            )
        }
        .onDisappear {
            #if canImport(AetherEngine)
            if !viewModel.isPreviewMode {
                aetherCoordinator.stop()
            }
            #endif
            viewModel.cleanup()
        }
        .onPlayPauseCommand {
            viewModel.togglePlayPause()
        }
        .onMoveCommand { direction in
            handleRemoteDirection(direction)
        }
        .onExitCommand {
            handleExit()
        }
    }

    // MARK: - Preview Still Backdrop Layer

    @ViewBuilder
    private var previewBackdropLayer: some View {
        ZStack {
            if let path = viewModel.backdropPath,
               let url = TMDBService.shared.imageURL(path: path, size: "w1280") {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .ignoresSafeArea()
                    }
                }
            }
            Color.black.opacity(0.28).ignoresSafeArea()
        }
    }

    // MARK: - Video Player Layer

    @ViewBuilder
    private var videoPlayerLayer: some View {
        if didResolveEnginePreference {
            #if canImport(AetherEngine)
            if viewModel.playerEngineName != "AVPlayer" && !aetherCoordinator.didFailInitialization {
                aetherPlayerView
            } else {
                avPlayerView
            }
            #else
            avPlayerView
            #endif
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    // MARK: - AetherEngine Integration

    #if canImport(AetherEngine)
    @ViewBuilder
    private var aetherPlayerView: some View {
        if let url = viewModel.streamURL {
            Group {
                if let engine = aetherCoordinator.engine {
                    AetherPlayerSurface(engine: engine)
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }
            }
            .onAppear {
                aetherCoordinator.load(url: url, viewModel: viewModel)
            }
            .onChange(of: viewModel.streamURL) { _, newURL in
                guard let newURL else { return }
                aetherCoordinator.load(url: newURL, viewModel: viewModel)
            }
            .onChange(of: viewModel.isPlaying) { _, shouldPlay in
                aetherCoordinator.syncPlayState(shouldPlay: shouldPlay)
            }
            .onChange(of: viewModel.seekTrigger) { _, targetTime in
                guard let targetTime else { return }
                viewModel.seekTrigger = nil
                aetherCoordinator.seek(to: targetTime)
            }
            .onDisappear { viewModel.engineAudioControlsActive = false }
            .onChange(of: viewModel.audioDelayMs) { _, ms in
                aetherCoordinator.engine?.setAudioDelay(Double(ms) / 1000)
            }
            .onChange(of: viewModel.selectedAudioTrackId) { _, trackId in
                aetherCoordinator.selectAudioTrack(trackId)
            }
            .onChange(of: viewModel.selectedSubtitleTrackId) { _, trackId in
                aetherCoordinator.selectSubtitleTrack(trackId)
            }
        }
    }
    #endif

    // MARK: - AVPlayer Fallback

    @ViewBuilder
    private var avPlayerView: some View {
        if let url = viewModel.streamURL {
            AVPlayerViewWrapper(
                url: url,
                viewModel: viewModel,
                resumeFrom: viewModel.resumeFromTime
            )
            .id(url)
            .ignoresSafeArea()
        }
    }

    // MARK: - Playback Error Overlay

    private func playbackErrorOverlay(message: String) -> some View {
        ZStack {
            Color.black.opacity(0.68).ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.white.opacity(0.92))

                Text("Unable to Play Stream")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.auraText)

                Text(message)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.auraSecondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 720)

                HStack(spacing: 18) {
                    if viewModel.playerEngineName != "AVPlayer" {
                        PlayerErrorActionButton(title: "Try AVPlayer Fallback", isPrimary: true) {
                            #if canImport(AetherEngine)
                            aetherCoordinator.stop()
                            #endif
                            viewModel.playbackError = nil
                            viewModel.isBuffering = true
                            viewModel.playerEngineName = "AVPlayer"
                        }
                    }

                    PlayerErrorActionButton(title: "Close", isPrimary: false) {
                        viewModel.cleanup()
                        dismiss()
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 36)
            .background(Color.auraSurface.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.auraGlassBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Remote Handling

    private func handleRemoteDirection(_ direction: MoveCommandDirection) {
        viewModel.showHUD()
        guard !viewModel.hasActiveModalOverlay else { return }

        switch direction {
        case .left:
            viewModel.seekBackward(seconds: 10)
        case .right:
            viewModel.seekForward(seconds: 10)
        case .up, .down:
            break
        @unknown default:
            break
        }
    }

    private func handleExit() {
        if viewModel.showSubtitleSyncSheet {
            viewModel.saveSubtitlePreferences()
            viewModel.showSubtitleSyncSheet = false
        } else if viewModel.showSubtitleStyleSheet {
            viewModel.saveSubtitlePreferences()
            viewModel.showSubtitleStyleSheet = false
        } else if viewModel.showStreamPicker {
            viewModel.showStreamPicker = false
        } else if viewModel.showAudioPicker || viewModel.showSubtitlePicker || viewModel.showInfoPanel {
            viewModel.showAudioPicker = false
            viewModel.showSubtitlePicker = false
            viewModel.showInfoPanel = false
        } else if viewModel.isHUDVisible && !viewModel.isPreviewMode {
            viewModel.hideHUD()
        } else {
            viewModel.cleanup()
            dismiss()
        }
    }
}

// MARK: - AetherEngine Player Coordinator

#if canImport(AetherEngine)
@MainActor
final class AetherPlayerCoordinator: ObservableObject {
    @Published private(set) var engine: AetherEngine?
    @Published private(set) var didFailInitialization: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private weak var boundViewModel: PlayerViewModel?
    private var loadTask: Task<Void, Never>?
    private var currentLoadedURL: URL?
    private var lastCues: [SubtitleCue] = []
    private var currentSourceTime: Double = 0
    private var didNotifyReadyForCurrentLoad: Bool = false

    func load(url: URL, viewModel: PlayerViewModel) {
        boundViewModel = viewModel

        if url == currentLoadedURL && engine != nil {
            return
        }

        guard let engine = ensureEngine() else {
            return
        }

        loadTask?.cancel()
        currentLoadedURL = url
        didNotifyReadyForCurrentLoad = false
        lastCues = []
        viewModel.playbackError = nil
        viewModel.onBufferingStarted()

        let startPos: Double? = viewModel.resumeFromTime > 0 ? viewModel.resumeFromTime : nil
        if startPos != nil {
            viewModel.resumeFromTime = 0
        }

        let options = LoadOptions(
            displayCriteriaOwner: .engine,
            dolbyVisionHandling: .automatic,
            matchContentEnabled: true,
            attemptsHDRMasterOnUnprovenPanel: true,
            audioBridgeMode: .surroundCompat,
            confirmAtmos: true
        )

        loadTask = Task { @MainActor [weak self, weak viewModel] in
            guard let self else { return }
            do {
                let probe = try await engine.load(
                    url: url,
                    startPosition: startPos,
                    options: options
                )
                guard !Task.isCancelled else { return }
                if let viewModel {
                    viewModel.engineAudioControlsActive = true
                    engine.setAudioDelay(Double(viewModel.audioDelayMs) / 1000)
                }
                if let viewModel, let probe, !self.didNotifyReadyForCurrentLoad, probe.durationSeconds > 0 {
                    viewModel.totalDuration = probe.durationSeconds
                }
            } catch is CancellationError {
                // Superseded by a newer load or teardown; not a playback error.
            } catch {
                guard !Task.isCancelled, let viewModel else { return }
                viewModel.onBufferingEnded()
                viewModel.playbackError = error.localizedDescription
            }
        }
    }

    func syncPlayState(shouldPlay: Bool) {
        guard let engine else { return }
        if shouldPlay {
            if engine.state == .paused {
                engine.play()
            }
        } else {
            if engine.state == .playing || engine.state == .seeking {
                engine.pause()
            }
        }
    }

    func seek(to seconds: Double) {
        guard let engine else { return }
        Task { @MainActor in
            await engine.seek(to: seconds)
        }
    }

    func selectAudioTrack(_ trackId: Int) {
        guard let engine,
              engine.activeAudioTrackIndex != trackId,
              engine.audioTracks.contains(where: { $0.id == trackId }) else { return }
        engine.selectAudioTrack(index: trackId)
    }

    func selectSubtitleTrack(_ trackId: Int) {
        guard let engine else { return }
        if trackId < 0 {
            engine.clearSubtitle()
            boundViewModel?.updateEmbeddedSubtitle(text: nil, bitmap: nil)
        } else if engine.subtitleTracks.contains(where: { $0.id == trackId && !$0.isExternal }) {
            engine.selectSubtitleTrack(index: trackId)
        }
    }

    func refreshEmbeddedSubtitleCue() {
        guard let vm = boundViewModel else { return }
        guard vm.selectedExternalSubtitle == nil, vm.selectedSubtitleTrackId >= 0 else {
            vm.updateEmbeddedSubtitle(text: nil, bitmap: nil)
            return
        }

        let adjustedTime = currentSourceTime - vm.subtitleSyncSettings.manualOffset
        let matching = lastCues.filter { adjustedTime >= $0.startTime && adjustedTime <= $0.endTime }

        let textParts = matching
            .compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let bitmap = matching.compactMap { cue -> CGImage? in
            if case .image(let img) = cue.body { return img.cgImage }
            return nil
        }.last

        vm.updateEmbeddedSubtitle(
            text: textParts.isEmpty ? nil : textParts.joined(separator: "\n"),
            bitmap: bitmap
        )
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        currentLoadedURL = nil
        lastCues = []
        cancellables.removeAll()
        engine?.stop()
        engine = nil
    }

    private func ensureEngine() -> AetherEngine? {
        if let engine { return engine }
        do {
            let instance = try AetherEngine()
            self.engine = instance
            bindPublishers(for: instance)
            return instance
        } catch {
            didFailInitialization = true
            boundViewModel?.playbackError = error.localizedDescription
            return nil
        }
    }

    private func bindPublishers(for engine: AetherEngine) {
        cancellables.removeAll()

        engine.clock.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak engine] time in
                MainActor.assumeIsolated {
                    guard let self, let vm = self.boundViewModel, let engine else { return }
                    vm.onTimeUpdate(current: time, total: engine.duration)
                }
            }
            .store(in: &cancellables)

        engine.clock.$sourceTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sourceTime in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.currentSourceTime = sourceTime
                    self.refreshEmbeddedSubtitleCue()
                }
            }
            .store(in: &cancellables)

        engine.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                MainActor.assumeIsolated {
                    guard let vm = self?.boundViewModel, duration > 0 else { return }
                    vm.totalDuration = duration
                }
            }
            .store(in: &cancellables)

        engine.$playbackPhase
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak engine] phase in
                MainActor.assumeIsolated {
                    guard let self, let vm = self.boundViewModel, let engine else { return }
                    switch phase {
                    case .idle:
                        break
                    case .loading, .rebuffering, .stalled, .seeking:
                        vm.onBufferingStarted()
                    case .playing:
                        vm.playbackError = nil
                        if !self.didNotifyReadyForCurrentLoad {
                            self.didNotifyReadyForCurrentLoad = true
                            vm.onPlaybackReady(duration: engine.duration)
                        } else {
                            vm.onBufferingEnded()
                            vm.isPlaying = true
                        }
                    case .paused:
                        if !self.didNotifyReadyForCurrentLoad, engine.duration > 0 {
                            self.didNotifyReadyForCurrentLoad = true
                            vm.onPlaybackReady(duration: engine.duration)
                        } else {
                            vm.onBufferingEnded()
                        }
                        vm.isPlaying = false
                    case .ended:
                        vm.onBufferingEnded()
                        vm.isPlaying = false
                        vm.saveProgress()
                    case .error(let message):
                        vm.onBufferingEnded()
                        vm.isPlaying = false
                        vm.playbackError = message
                    }
                }
            }
            .store(in: &cancellables)

        engine.$videoFormat
            .receive(on: DispatchQueue.main)
            .sink { [weak self] format in
                MainActor.assumeIsolated {
                    guard let vm = self?.boundViewModel else { return }
                    switch format {
                    case .dolbyVision: vm.videoDynamicRangeBadge = "Dolby Vision"
                    case .hdr10Plus:   vm.videoDynamicRangeBadge = "HDR10+"
                    case .hdr10:       vm.videoDynamicRangeBadge = "HDR10"
                    case .hlg:         vm.videoDynamicRangeBadge = "HLG"
                    case .sdr:         vm.videoDynamicRangeBadge = nil
                    }
                }
            }
            .store(in: &cancellables)

        engine.$audioTracks
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak engine] tracks in
                MainActor.assumeIsolated {
                    guard let vm = self?.boundViewModel else { return }
                    vm.availableAudioTracks = tracks.map { track in
                        var details: [String] = []
                        if !track.name.isEmpty {
                            details.append(track.name)
                        } else if let profile = track.profile, !profile.isEmpty {
                            details.append(profile)
                        } else if !track.codec.isEmpty {
                            details.append(track.codec.uppercased())
                        }
                        if track.isAtmos && !details.joined().localizedCaseInsensitiveContains("Atmos") {
                            details.append("Atmos")
                        } else if track.isDTSX && !details.joined().localizedCaseInsensitiveContains("DTS:X") {
                            details.append("DTS:X")
                        } else if track.channels > 0 && !details.joined().contains("5.1") && !details.joined().contains("7.1") {
                            let layout = track.channels == 8 ? "7.1" : (track.channels == 6 ? "5.1" : "\(track.channels)ch")
                            details.append(layout)
                        }
                        return MediaTrack(
                            id: track.id,
                            name: details.isEmpty ? "Track \(track.id)" : details.joined(separator: " · "),
                            language: track.language?.uppercased(),
                            isDefault: track.isDefault
                        )
                    }
                    if let activeId = engine?.activeAudioTrackIndex {
                        vm.selectedAudioTrackId = activeId
                    } else if let firstDefault = tracks.first(where: { $0.isDefault }) {
                        vm.selectedAudioTrackId = firstDefault.id
                    }
                }
            }
            .store(in: &cancellables)

        engine.$activeAudioTrackIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activeId in
                MainActor.assumeIsolated {
                    guard let vm = self?.boundViewModel, let activeId else { return }
                    if vm.selectedAudioTrackId != activeId {
                        vm.selectedAudioTrackId = activeId
                    }
                }
            }
            .store(in: &cancellables)

        engine.$subtitleTracks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tracks in
                MainActor.assumeIsolated {
                    guard let vm = self?.boundViewModel else { return }
                    vm.availableSubtitleTracks = tracks
                        .filter { !$0.isExternal }
                        .map { track in
                            var nameParts: [String] = []
                            if !track.name.isEmpty {
                                nameParts.append(track.name)
                            } else if !track.codec.isEmpty {
                                nameParts.append(track.codec.uppercased())
                            }
                            if track.isHearingImpaired { nameParts.append("SDH") }
                            if track.isForced { nameParts.append("Forced") }
                            return MediaTrack(
                                id: track.id,
                                name: nameParts.isEmpty ? "Subtitle \(track.id)" : nameParts.joined(separator: " · "),
                                language: track.language?.uppercased(),
                                isDefault: track.isDefault
                            )
                        }
                }
            }
            .store(in: &cancellables)

        engine.$activeSubtitleTrackIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activeId in
                MainActor.assumeIsolated {
                    guard let vm = self?.boundViewModel, vm.selectedExternalSubtitle == nil else { return }
                    let resolved = activeId ?? -1
                    if vm.selectedSubtitleTrackId != resolved {
                        vm.selectedSubtitleTrackId = resolved
                    }
                }
            }
            .store(in: &cancellables)

        engine.$subtitleCues
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cues in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.lastCues = cues
                    self.refreshEmbeddedSubtitleCue()
                }
            }
            .store(in: &cancellables)
    }
}
#endif

// MARK: - AVPlayer Wrapper (Fallback Engine)

struct AVPlayerViewWrapper: UIViewControllerRepresentable {
    let url: URL
    let viewModel: PlayerViewModel
    let resumeFrom: Double

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        controller.player = player

        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player else { return }
            let current = CMTimeGetSeconds(time)
            let total = CMTimeGetSeconds(player.currentItem?.duration ?? .zero)
            if !current.isNaN && !total.isNaN {
                Task { @MainActor in
                    viewModel.onTimeUpdate(current: current, total: total)
                }
            }
        }

        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { status in
                guard status == .failed else { return }
                viewModel.isBuffering = false
                viewModel.isPlaying = false
                viewModel.playbackError = playerItem.error?.localizedDescription
                    ?? "The stream could not be played."
            }
            .store(in: &context.coordinator.cancellables)

        playerItem.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { empty in
                if empty { viewModel.onBufferingStarted() }
            }
            .store(in: &context.coordinator.cancellables)

        playerItem.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { ready in
                if ready {
                    let total = CMTimeGetSeconds(playerItem.duration)
                    if !total.isNaN && total > 0 {
                        viewModel.onPlaybackReady(duration: total)
                    }
                }
            }
            .store(in: &context.coordinator.cancellables)

        if resumeFrom > 0 {
            player.seek(to: CMTime(seconds: resumeFrom, preferredTimescale: 1))
        }

        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if viewModel.isPlaying {
            controller.player?.play()
        } else {
            controller.player?.pause()
        }

        if let targetTime = viewModel.seekTrigger {
            controller.player?.seek(to: CMTime(seconds: targetTime, preferredTimescale: 1))
            Task { @MainActor in
                viewModel.seekTrigger = nil
            }
        }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.player?.pause()
        controller.player = nil
        coordinator.cancellables.removeAll()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var cancellables = Set<AnyCancellable>()
    }
}

private struct PlayerErrorActionButton: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isFocused || isPrimary ? Color.black : Color.auraText)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(
                    isFocused || isPrimary
                        ? Color.white.opacity(isFocused ? 1.0 : 0.88)
                        : Color.auraGlassFill
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isFocused ? Color.white : Color.auraGlassBorder, lineWidth: isFocused ? 2 : 1)
                )
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(.easeOut(duration: 0.16), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
    }
}
