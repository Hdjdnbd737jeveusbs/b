import SwiftUI
import SwiftData
import AVKit
import AVFoundation
#if canImport(KSPlayer)
import KSPlayer
#else
import Combine
#endif

// MARK: - Player View

struct PlayerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: PlayerViewModel

    #if canImport(KSPlayer)
    @StateObject private var ksCoordinator = KSVideoPlayer.Coordinator()
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
            if viewModel.isBuffering && viewModel.hasStartedPlayback && !viewModel.isPreviewMode {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            viewModel.loadSubtitleSettingsFromPreferences(context: modelContext)
            viewModel.startPeriodicSave(context: modelContext)
        }
        .onChange(of: viewModel.subtitleSyncSettings) { _, _ in
            viewModel.saveSubtitlePreferences()
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
            #if canImport(KSPlayer)
            if !viewModel.isPreviewMode {
                ksCoordinator.resetPlayer()
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
        #if canImport(KSPlayer)
        ksPlayerView
        #else
        avPlayerView
        #endif
    }

    // MARK: - KSPlayer Integration

    #if canImport(KSPlayer)
    @ViewBuilder
    private var ksPlayerView: some View {
        if let url = viewModel.streamURL {
            KSVideoPlayer(coordinator: ksCoordinator, url: url, options: playerOptions)
                .onStateChanged { layer, state in
                    Task { @MainActor in
                        handleKSPlayerState(layer: layer, state: state)
                    }
                }
                .onPlay { currentTime, totalTime in
                    Task { @MainActor in
                        viewModel.onTimeUpdate(current: currentTime, total: totalTime)
                    }
                }
                .onFinish { _, _ in
                    Task { @MainActor in
                        viewModel.isPlaying = false
                        viewModel.saveProgress()
                    }
                }
                .onBufferChanged { _, _ in }
                .onChange(of: viewModel.isPlaying) { _, shouldPlay in
                    guard let layer = ksCoordinator.playerLayer else { return }
                    if shouldPlay && !layer.player.isPlaying {
                        layer.play()
                    } else if !shouldPlay && layer.player.isPlaying {
                        layer.pause()
                    }
                }
                .onChange(of: viewModel.seekTrigger) { _, targetTime in
                    guard let targetTime else { return }
                    ksCoordinator.seek(time: targetTime)
                    viewModel.seekTrigger = nil
                }
                .onChange(of: viewModel.selectedAudioTrackId) { _, trackId in
                    selectKSPlayerTrack(trackId: trackId, mediaType: .audio)
                }
                .onChange(of: viewModel.selectedSubtitleTrackId) { _, trackId in
                    selectKSPlayerTrack(trackId: trackId, mediaType: .subtitle)
                }
                .ignoresSafeArea()
        }
    }

    private var playerOptions: KSOptions {
        KSOptions.isAutoPlay = true
        let options = KSOptions()
        options.hardwareDecode = true
        options.isAccurateSeek = true
        if viewModel.resumeFromTime > 0 {
            options.startPlayTime = TimeInterval(viewModel.resumeFromTime)
        }
        return options
    }

    @MainActor
    private func handleKSPlayerState(layer: KSPlayerLayer, state: KSPlayerState) {
        switch state {
        case .buffering:
            viewModel.onBufferingStarted()
        case .bufferFinished:
            viewModel.onBufferingEnded()
        case .readyToPlay:
            let duration = layer.player.duration
            loadKSPlayerTracks(from: layer.player)
            viewModel.onPlaybackReady(duration: duration)
        case .paused:
            viewModel.isPlaying = false
        case .playedToTheEnd:
            viewModel.isPlaying = false
            viewModel.saveProgress()
        default:
            break
        }
    }

    @MainActor
    private func loadKSPlayerTracks(from player: MediaPlayerProtocol) {
        let audioTracks = player.tracks(mediaType: .audio).map { track in
            MediaTrack(
                id: Int(track.trackID),
                name: track.name,
                language: track.languageCode,
                isDefault: track.isEnabled
            )
        }
        viewModel.availableAudioTracks = audioTracks
        if let activeAudio = audioTracks.first(where: { $0.isDefault }) {
            viewModel.selectedAudioTrackId = activeAudio.id
        }

        let subTracks = player.tracks(mediaType: .subtitle).map { track in
            MediaTrack(
                id: Int(track.trackID),
                name: track.name,
                language: track.languageCode,
                isDefault: track.isEnabled
            )
        }
        viewModel.availableSubtitleTracks = subTracks
    }

    @MainActor
    private func selectKSPlayerTrack(trackId: Int, mediaType: AVFoundation.AVMediaType) {
        guard let player = ksCoordinator.playerLayer?.player else { return }
        let tracks = player.tracks(mediaType: mediaType)
        if trackId == -1 {
            for track in tracks {
                track.isEnabled = false
            }
            return
        }
        if let target = tracks.first(where: { Int($0.trackID) == trackId }) {
            player.select(track: target)
        }
    }
    #endif

    // MARK: - AVPlayer Fallback

    #if !canImport(KSPlayer)
    @State private var avPlayer: AVPlayer?

    @ViewBuilder
    private var avPlayerView: some View {
        if let url = viewModel.streamURL {
            AVPlayerViewWrapper(
                url: url,
                viewModel: viewModel,
                resumeFrom: viewModel.resumeFromTime
            )
            .ignoresSafeArea()
        }
    }
    #endif

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

// MARK: - AVPlayer Wrapper (Fallback when KSPlayer is not available)

#if !canImport(KSPlayer)
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

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var cancellables = Set<AnyCancellable>()
    }
}
#endif
