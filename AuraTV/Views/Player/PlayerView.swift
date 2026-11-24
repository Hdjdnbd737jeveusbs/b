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
            Color.black.ignoresSafeArea()

            // Video Player Layer
            videoPlayerLayer

            // Subtitle Overlay Layer (Phase 3)
            SubtitleOverlayView(
                currentCue: viewModel.currentSubtitleCue,
                style: viewModel.subtitleStyle,
                fixRTL: viewModel.subtitleSyncSettings.fixRTL,
                fixReversedPunctuation: viewModel.subtitleSyncSettings.fixReversedPunctuation
            )

            // Loading Overlay (shown while buffering & no playback yet)
            if viewModel.isBuffering && !viewModel.hasStartedPlayback {
                LoadingOverlayView(
                    title: viewModel.title,
                    backdropPath: viewModel.backdropPath
                )
                .transition(.opacity)
            }

            // Player HUD (shown on user interaction)
            if viewModel.hasStartedPlayback {
                PlayerHUDView(viewModel: viewModel)
                    .opacity(viewModel.isHUDVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.isHUDVisible)
            }

            // Buffering indicator during playback
            if viewModel.isBuffering && viewModel.hasStartedPlayback {
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
        .sheet(isPresented: $viewModel.showSubtitleSyncSheet) {
            SubtitleSyncSheet(
                settings: $viewModel.subtitleSyncSettings,
                onSyncNow: {
                    Task {
                        await viewModel.performSyncNow()
                    }
                },
                onDismiss: { viewModel.showSubtitleSyncSheet = false }
            )
        }
        .sheet(isPresented: $viewModel.showSubtitleStyleSheet) {
            SubtitleStyleSheet(
                style: $viewModel.subtitleStyle,
                onDismiss: { viewModel.showSubtitleStyleSheet = false }
            )
        }
        .onDisappear {
            #if canImport(KSPlayer)
            ksCoordinator.resetPlayer()
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
        // Start from resume point
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
        if viewModel.showAudioPicker || viewModel.showSubtitlePicker || viewModel.showInfoPanel {
            viewModel.showAudioPicker = false
            viewModel.showSubtitlePicker = false
            viewModel.showInfoPanel = false
        } else if viewModel.isHUDVisible {
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
        controller.showsPlaybackControls = false // We use our own HUD

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        controller.player = player

        // Observe time
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

        // Observe buffering
        playerItem.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { empty in
                if empty {
                    viewModel.onBufferingStarted()
                }
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

        // Resume from saved position
        if resumeFrom > 0 {
            player.seek(to: CMTime(seconds: resumeFrom, preferredTimescale: 1))
        }

        player.play()

        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        // Sync play/pause state
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
