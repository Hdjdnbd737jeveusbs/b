import SwiftUI

// MARK: - Player HUD View (Infuse-style)

/// Full-screen overlay HUD matching the reference screenshot:
/// - Top-left: letter-spaced title ("S K Y F A L L")
/// - Bottom: timeline scrub bar with current/remaining time
/// - Bottom-right: 5 circular icon buttons (subtitles, font, audio, chapters, info)
/// - Top/bottom black bars for cinematic feel

struct PlayerHUDView: View {
    @Bindable var viewModel: PlayerViewModel

    @FocusState private var focusedControl: HUDControl?
    @FocusState private var focusedTrackId: String?

    enum HUDControl: Hashable {
        case timeline
        case subtitles
        case fontStyle
        case audio
        case chapters
        case info
    }

    var body: some View {
        ZStack {
            // Top black bar
            VStack {
                topBar
                Spacer()
            }

            // Bottom area: timeline + controls
            VStack {
                Spacer()
                bottomBar
            }

            // Subtitle picker overlay
            if viewModel.showSubtitlePicker {
                subtitlePickerOverlay
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Audio picker overlay
            if viewModel.showAudioPicker {
                audioPickerOverlay
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .onTapGesture {
            viewModel.toggleHUD()
        }
    }

    // MARK: - Top Bar

    @ViewBuilder
    private var topBar: some View {
        ZStack(alignment: .topLeading) {
            // Gradient bar
            LinearGradient(
                gradient: Gradient(colors: [.black.opacity(0.8), .clear]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 140)

            // Title
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.title.uppercased())
                    .font(.system(size: 32, weight: .bold))
                    .tracking(10)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 2)

                // Episode info if series
                if let season = viewModel.seasonNumber,
                   let episode = viewModel.episodeNumber {
                    HStack(spacing: 6) {
                        Text("S\(season):E\(episode)")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        if let epTitle = viewModel.episodeTitle {
                            Text("·")
                                .foregroundStyle(.white.opacity(0.5))
                            Text(epTitle)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
            .padding(.leading, 60)
            .padding(.top, 50)
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        ZStack(alignment: .bottom) {
            // Bottom gradient
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.85)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)

            VStack(spacing: 16) {
                // Control buttons row (Above the timeline, aligned right, matching Screenshot 4)
                HStack {
                    Spacer()
                    controlButtons
                }

                // Timeline scrub bar
                timelineBar

                // Current & Remaining timestamps row (Below timeline, matching Screenshot 4)
                HStack {
                    Text(viewModel.currentTimeFormatted)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer()

                    Text(viewModel.remainingTimeFormatted)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 45)
        }
    }

    // MARK: - Timeline Bar

    @ViewBuilder
    private var timelineBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 6)

                // Progress track
                Capsule()
                    .fill(Color.white)
                    .frame(width: geometry.size.width * viewModel.progress, height: 6)

                // Scrub handle (visible on focus)
                Circle()
                    .fill(Color.white)
                    .frame(width: focusedControl == .timeline ? 20 : 0, height: focusedControl == .timeline ? 20 : 0)
                    .offset(x: (geometry.size.width * viewModel.progress) - 10)
                    .animation(.easeInOut(duration: 0.2), value: focusedControl)
            }
        }
        .frame(height: 20)
        .focusable()
        .focused($focusedControl, equals: .timeline)
    }

    // MARK: - Control Buttons

    @ViewBuilder
    private var controlButtons: some View {
        HStack(spacing: 16) {
            // Subtitles (Highlights white with dark icon when active, matching Screenshot 4)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.showSubtitlePicker.toggle()
                    viewModel.showAudioPicker = false
                }
            }) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle((viewModel.selectedExternalSubtitle != nil || viewModel.selectedSubtitleTrackId != -1) ? Color.black : Color.white)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill((viewModel.selectedExternalSubtitle != nil || viewModel.selectedSubtitleTrackId != -1) ? Color.white : Color.white.opacity(focusedControl == .subtitles ? 0.3 : 0.12))
                    )
                    .overlay(
                        Circle()
                            .stroke(focusedControl == .subtitles ? Color.white : Color.clear, lineWidth: 2)
                    )
                    .scaleEffect(focusedControl == .subtitles ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: focusedControl)
            }
            .buttonStyle(.plain)
            .focused($focusedControl, equals: .subtitles)

            // Font Style ("Aa" text button matching Screenshot 4)
            Button(action: {
                viewModel.showSubtitleStyleSheet = true
                viewModel.showSubtitlePicker = false
                viewModel.showAudioPicker = false
            }) {
                Text("Aa")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(focusedControl == .fontStyle ? 0.3 : 0.12))
                    )
                    .overlay(
                        Circle()
                            .stroke(focusedControl == .fontStyle ? Color.white : Color.clear, lineWidth: 1.5)
                    )
                    .scaleEffect(focusedControl == .fontStyle ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: focusedControl)
            }
            .buttonStyle(.plain)
            .focused($focusedControl, equals: .fontStyle)

            // Audio (Equalizer waveform matching Screenshot 4)
            hudButton(
                icon: "waveform",
                control: .audio,
                action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.showAudioPicker.toggle()
                        viewModel.showSubtitlePicker = false
                    }
                }
            )

            // Chapters (Rectangle list matching Screenshot 4)
            hudButton(
                icon: "list.bullet.rectangle",
                control: .chapters,
                action: { /* Chapters */ }
            )

            // Info (Info circle matching Screenshot 4)
            hudButton(
                icon: "info.circle",
                control: .info,
                action: {
                    viewModel.showInfoPanel.toggle()
                }
            )
        }
    }

    @ViewBuilder
    private func hudButton(icon: String, control: HUDControl, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(Color.white.opacity(focusedControl == control ? 0.3 : 0.12))
                )
                .overlay(
                    Circle()
                        .stroke(focusedControl == control ? Color.white.opacity(0.6) : Color.clear, lineWidth: 1.5)
                )
                .scaleEffect(focusedControl == control ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: focusedControl)
        }
        .buttonStyle(.plain)
        .focused($focusedControl, equals: control)
    }

    // MARK: - Subtitle Picker Overlay (Phase 3)

    @ViewBuilder
    private var subtitlePickerOverlay: some View {
        VStack(alignment: .trailing) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                // Search Bar (White pill matching Screenshot 5)
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.75))

                    TextField("Search Subtitles...", text: $viewModel.subtitleSearchText)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.black)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.white)
                .clipShape(Capsule())
                .padding(.horizontal, 18)
                .padding(.top, 18)

                // Subtitle Quick Actions (Sync & Style)
                HStack(spacing: 12) {
                    Button(action: {
                        viewModel.showSubtitleSyncSheet = true
                        viewModel.showSubtitlePicker = false
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.2.square")
                            Text("Sync")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        viewModel.showSubtitleStyleSheet = true
                        viewModel.showSubtitlePicker = false
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "textformat.size")
                            Text("Styling")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)

                Divider().background(Color.white.opacity(0.15))

                // Scrollable Tracks List
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        // "Off" option
                        trackRow(
                            id: "off",
                            name: "Off",
                            isSelected: viewModel.selectedExternalSubtitle == nil && viewModel.selectedSubtitleTrackId == -1,
                            action: {
                                Task {
                                    await viewModel.selectExternalSubtitleTrack(nil)
                                    viewModel.selectSubtitleTrack(-1)
                                }
                            }
                        )

                        // External Subtitles (Arabic & Multi-Source)
                        if viewModel.isFetchingSubtitles {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                                Text("Fetching online subtitles...")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.auraSecondaryText)
                            }
                            .padding(16)
                        } else {
                            ForEach(viewModel.filteredSubtitleTracks) { track in
                                trackRow(
                                    id: track.id,
                                    name: track.displayName,
                                    isSelected: viewModel.selectedExternalSubtitle?.id == track.id,
                                    action: {
                                        Task {
                                            await viewModel.selectExternalSubtitleTrack(track)
                                        }
                                    }
                                )
                            }
                        }

                        // Embedded Subtitles from stream
                        if !viewModel.availableSubtitleTracks.isEmpty {
                            Divider().background(Color.white.opacity(0.1))
                                .padding(.vertical, 4)

                            ForEach(viewModel.availableSubtitleTracks) { embeddedTrack in
                                trackRow(
                                    id: "stream_\(embeddedTrack.id)",
                                    name: "\(embeddedTrack.displayName) [Stream]",
                                    isSelected: viewModel.selectedSubtitleTrackId == embeddedTrack.id && viewModel.selectedExternalSubtitle == nil,
                                    action: {
                                        Task {
                                            await viewModel.selectExternalSubtitleTrack(nil)
                                            viewModel.selectSubtitleTrack(embeddedTrack.id)
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .frame(maxHeight: 380)
            }
            .frame(width: 480)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(white: 0.12))
            )
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.6), radius: 24, x: 0, y: 10)
            .padding(.trailing, 60)
            .padding(.bottom, 170)
        }
    }

    // MARK: - Audio Picker Overlay

    @ViewBuilder
    private var audioPickerOverlay: some View {
        VStack(alignment: .trailing) {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                // Header
                Text("Audio")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                Divider().background(Color.white.opacity(0.15))

                // Audio tracks
                ForEach(viewModel.availableAudioTracks) { track in
                    trackRow(
                        id: "audio_\(track.id)",
                        name: track.displayName,
                        isSelected: viewModel.selectedAudioTrackId == track.id,
                        action: { viewModel.selectAudioTrack(track.id) }
                    )
                }

                if viewModel.availableAudioTracks.isEmpty {
                    Text("No audio tracks detected")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(20)
                }
            }
            .frame(width: 400)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.trailing, 60)
            .padding(.bottom, 180)
        }
    }

    // MARK: - Track Row

    @ViewBuilder
    private func trackRow(id: String, name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let isFocused = focusedTrackId == id

        Button(action: action) {
            HStack(spacing: 12) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isFocused ? Color.black : Color.white)
                        .frame(width: 18)
                } else {
                    Spacer().frame(width: 18)
                }

                Text(name)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isFocused ? Color.black : Color.white)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? Color.white : (isSelected ? Color.white.opacity(0.12) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .focused($focusedTrackId, equals: id)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
