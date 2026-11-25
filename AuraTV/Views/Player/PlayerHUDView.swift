import SwiftUI

// MARK: - Player HUD View (Dark Cinema Glassmorphic HUD)

struct PlayerHUDView: View {
    @Bindable var viewModel: PlayerViewModel

    @FocusState private var focusedControl: HUDControl?
    @FocusState private var focusedTrackId: String?

    enum HUDControl: Hashable {
        case playPause
        case skipBack
        case skipForward
        case timeline
        case streams
        case audio
        case subtitles
        case subtitleSync
        case fontStyle
        case info
        case skipIntro
        case playNext
        case dismissUpNext
    }

    var body: some View {
        ZStack {
            // Top bar: Title + Episode info + Tech Badges
            VStack {
                topBar
                Spacer()
            }

            // Floating Skip Intro / Skip Credits + Up Next Overlay
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    if viewModel.showSkipIntroPill {
                        skipPill(
                            title: viewModel.skipIntroCountdownRemaining.map { "Skip Intro (\($0)s)" } ?? "Skip Intro",
                            icon: "forward.fill",
                            control: .skipIntro,
                            action: { viewModel.skipIntro() }
                        )
                    } else if viewModel.showSkipCreditsPill {
                        skipPill(
                            title: "Skip Credits",
                            icon: "forward.end.fill",
                            control: .skipIntro,
                            action: { viewModel.skipCredits() }
                        )
                    }

                    Spacer()

                    if viewModel.showUpNextOverlay, let nextEp = viewModel.nextEpisode {
                        upNextCard(episode: nextEp)
                    }
                }
                .padding(.horizontal, 70)
                .padding(.bottom, 210)
            }

            // Bottom transport & scrubber bar
            VStack {
                Spacer()
                bottomBar
            }

            // Subtitle picker popover
            if viewModel.showSubtitlePicker {
                subtitlePickerOverlay
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Audio picker popover
            if viewModel.showAudioPicker {
                audioPickerOverlay
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Media & Stream Info popover
            if viewModel.showInfoPanel {
                infoPanelOverlay
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
            LinearGradient(
                gradient: Gradient(colors: [Color.auraBackground.opacity(0.92), .clear]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 165)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.title.uppercased())
                        .font(.system(size: 32, weight: .bold))
                        .tracking(8)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.75), radius: 8, x: 0, y: 2)

                    if let season = viewModel.seasonNumber,
                       let episode = viewModel.episodeNumber {
                        HStack(spacing: 8) {
                            Text("S\(season) • E\(episode)")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))

                            if let epTitle = viewModel.episodeTitle, !epTitle.isEmpty {
                                Text("-")
                                    .foregroundStyle(.white.opacity(0.55))
                                Text(epTitle)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.78))
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                Spacer()

                // Technical Badges (4K, HDR10/Dolby Vision, 5.1/Atmos)
                HStack(spacing: 8) {
                    ForEach(viewModel.activeTechBadges, id: \.self) { badge in
                        BadgeView(text: badge, style: .outlined, fontSize: 12)
                    }
                    if let fileSize = viewModel.selectedStream?.parsedInfo.fileSize {
                        BadgeView(text: fileSize, style: .translucent, fontSize: 12)
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 70)
            .padding(.top, 48)
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                gradient: Gradient(colors: [.clear, Color.auraBackground.opacity(0.95)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 240)

            VStack(spacing: 16) {
                // Transport & Quick-Action Glass Pills Row
                HStack(spacing: 14) {
                    // Left cluster: Skip -10s, Play/Pause, Skip +10s
                    HStack(spacing: 12) {
                        transportButton(icon: "gobackward.10", control: .skipBack) {
                            viewModel.seekBackward(seconds: 10)
                        }

                        transportButton(
                            icon: viewModel.isPlaying ? "pause.fill" : "play.fill",
                            control: .playPause,
                            isProminent: true
                        ) {
                            viewModel.togglePlayPause()
                        }

                        transportButton(icon: "goforward.10", control: .skipForward) {
                            viewModel.seekForward(seconds: 10)
                        }
                    }

                    Spacer()

                    // Right cluster: Streams, Audio, Subtitles, Subtitle Sync, Aa, Info
                    HStack(spacing: 12) {
                        if !viewModel.availableStreams.isEmpty {
                            quickActionPill(
                                icon: "tv.and.mediabox",
                                label: viewModel.selectedStream?.parsedInfo.resolution.displayName ?? "Streams",
                                isActive: viewModel.showStreamPicker,
                                control: .streams
                            ) {
                                viewModel.showStreamPicker = true
                                viewModel.showSubtitlePicker = false
                                viewModel.showAudioPicker = false
                                viewModel.showInfoPanel = false
                            }
                        }

                        quickActionPill(
                            icon: "waveform",
                            label: "Audio",
                            isActive: viewModel.showAudioPicker,
                            control: .audio
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                viewModel.showAudioPicker.toggle()
                                viewModel.showSubtitlePicker = false
                                viewModel.showInfoPanel = false
                            }
                        }

                        quickActionPill(
                            icon: "captions.bubble.fill",
                            label: "Subtitles",
                            isActive: viewModel.showSubtitlePicker || viewModel.selectedExternalSubtitle != nil || viewModel.selectedSubtitleTrackId != -1,
                            control: .subtitles
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                viewModel.showSubtitlePicker.toggle()
                                viewModel.showAudioPicker = false
                                viewModel.showInfoPanel = false
                            }
                        }

                        quickActionPill(
                            icon: "slider.horizontal.2.square",
                            label: "Sync",
                            isActive: viewModel.showSubtitleSyncSheet,
                            control: .subtitleSync
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                viewModel.showSubtitleSyncSheet = true
                                viewModel.showSubtitlePicker = false
                                viewModel.showAudioPicker = false
                                viewModel.showInfoPanel = false
                            }
                        }

                        quickActionPill(
                            icon: nil,
                            label: "Aa",
                            isActive: viewModel.showSubtitleStyleSheet,
                            control: .fontStyle
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                viewModel.showSubtitleStyleSheet = true
                                viewModel.showSubtitlePicker = false
                                viewModel.showAudioPicker = false
                                viewModel.showInfoPanel = false
                            }
                        }

                        hudCircleButton(
                            icon: "info.circle",
                            isActive: viewModel.showInfoPanel,
                            control: .info
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                viewModel.showInfoPanel.toggle()
                                viewModel.showSubtitlePicker = false
                                viewModel.showAudioPicker = false
                            }
                        }
                    }
                }

                // Scrubber Timeline Bar
                timelineBar

                // Elapsed & Remaining Timestamps
                HStack {
                    Text(viewModel.currentTimeFormatted)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))

                    Spacer()

                    Text(viewModel.remainingTimeFormatted)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .padding(.horizontal, 70)
            .padding(.bottom, 42)
        }
    }

    // MARK: - Timeline Scrubber

    @ViewBuilder
    private var timelineBar: some View {
        let isFocused = focusedControl == .timeline

        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.24))
                    .frame(height: isFocused ? 9 : 6)

                Capsule()
                    .fill(Color.white)
                    .frame(width: geometry.size.width * viewModel.progress, height: isFocused ? 9 : 6)

                Circle()
                    .fill(Color.white)
                    .frame(width: isFocused ? 22 : 12, height: isFocused ? 22 : 12)
                    .shadow(color: .black.opacity(0.6), radius: 6)
                    .offset(x: max(0, (geometry.size.width * viewModel.progress) - (isFocused ? 11 : 6)))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.16), value: isFocused)
        }
        .frame(height: 24)
        .focusable()
        .focused($focusedControl, equals: .timeline)
        .onMoveCommand { direction in
            guard isFocused else { return }
            switch direction {
            case .left:
                viewModel.seekBackward(seconds: 15)
            case .right:
                viewModel.seekForward(seconds: 15)
            default:
                break
            }
        }
    }

    // MARK: - Transport & Action Controls

    @ViewBuilder
    private func transportButton(
        icon: String,
        control: HUDControl,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focusedControl == control
        let size: CGFloat = isProminent ? 52 : 46

        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: isProminent ? 21 : 18, weight: .bold))
                .foregroundStyle(isFocused ? Color.black : Color.white)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(isFocused ? Color.white : Color.white.opacity(0.14))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                )
                .scaleEffect(isFocused ? 1.12 : 1.0)
                .animation(.easeOut(duration: 0.16), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedControl, equals: control)
    }

    @ViewBuilder
    private func quickActionPill(
        icon: String?,
        label: String,
        isActive: Bool,
        control: HUDControl,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focusedControl == control

        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(isFocused || isActive ? Color.black : Color.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(isFocused || isActive ? Color.white : Color.white.opacity(0.14))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(isFocused ? 1.0 : 0.24), lineWidth: isFocused ? 2 : 1)
            )
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .animation(.easeOut(duration: 0.16), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedControl, equals: control)
    }

    @ViewBuilder
    private func hudCircleButton(
        icon: String,
        isActive: Bool,
        control: HUDControl,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focusedControl == control

        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isFocused || isActive ? Color.black : Color.white)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(isFocused || isActive ? Color.white : Color.white.opacity(0.14))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                )
                .scaleEffect(isFocused ? 1.12 : 1.0)
                .animation(.easeOut(duration: 0.16), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedControl, equals: control)
    }

    // MARK: - Skip Pill & Up Next Card

    @ViewBuilder
    private func skipPill(
        title: String,
        icon: String,
        control: HUDControl,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focusedControl == control

        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: Capsule())
            .background(isFocused ? Color.white : Color.white.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(isFocused ? 1.0 : 0.35), lineWidth: isFocused ? 2.5 : 1)
            )
            .scaleEffect(isFocused ? 1.07 : 1.0)
            .animation(.easeOut(duration: 0.16), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedControl, equals: control)
    }

    @ViewBuilder
    private func upNextCard(episode: TMDBEpisode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("UP NEXT")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Text("Starting in \(viewModel.upNextCountdownRemaining)s")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.16), in: Capsule())
            }

            Text("S\(episode.seasonNumber) • E\(episode.episodeNumber) — \(episode.name)")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 12) {
                Button {
                    viewModel.playNextEpisodeNow()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Play Next")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.white, in: Capsule())
                    .scaleEffect(focusedControl == .playNext ? 1.06 : 1.0)
                }
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()
                .focused($focusedControl, equals: .playNext)

                Button {
                    viewModel.dismissUpNext()
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(focusedControl == .dismissUpNext ? Color.white.opacity(0.28) : Color.white.opacity(0.12))
                        )
                        .overlay(
                            Capsule().stroke(focusedControl == .dismissUpNext ? Color.white : Color.clear, lineWidth: 2)
                        )
                }
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()
                .focused($focusedControl, equals: .dismissUpNext)
            }
        }
        .padding(22)
        .frame(width: 430)
        .background(Color.auraSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.65), radius: 22, y: 8)
    }

    // MARK: - Subtitle Picker Popover

    @ViewBuilder
    private var subtitlePickerOverlay: some View {
        VStack(alignment: .trailing) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                // Search Subtitles bar
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
                .background(Color.white, in: Capsule())
                .padding(.horizontal, 18)
                .padding(.top, 18)

                // Sync & Styling shortcut pills
                HStack(spacing: 12) {
                    Button {
                        viewModel.showSubtitleSyncSheet = true
                        viewModel.showSubtitlePicker = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.2.square")
                            Text("Subtitle Sync")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(AuraButtonStyle())
                    .focusEffectDisabled()

                    Button {
                        viewModel.showSubtitleStyleSheet = true
                        viewModel.showSubtitlePicker = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "textformat.size")
                            Text("Appearance")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(AuraButtonStyle())
                    .focusEffectDisabled()
                }
                .padding(.horizontal, 18)

                Divider().background(Color.white.opacity(0.15))

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        trackRow(
                            id: "off",
                            name: "Off",
                            isSelected: viewModel.selectedExternalSubtitle == nil && viewModel.selectedSubtitleTrackId == -1
                        ) {
                            Task {
                                await viewModel.selectExternalSubtitleTrack(nil)
                                viewModel.selectSubtitleTrack(-1)
                            }
                        }

                        if viewModel.isFetchingSubtitles {
                            HStack(spacing: 10) {
                                ProgressView().scaleEffect(0.8).tint(.white)
                                Text("Searching SubDL, OpenSubtitles & Wyzie...")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.auraSecondaryText)
                            }
                            .padding(16)
                        } else {
                            ForEach(viewModel.filteredSubtitleTracks) { track in
                                trackRow(
                                    id: track.id,
                                    name: track.displayName,
                                    isSelected: viewModel.selectedExternalSubtitle?.id == track.id
                                ) {
                                    Task {
                                        await viewModel.selectExternalSubtitleTrack(track)
                                    }
                                }
                            }
                        }

                        if !viewModel.availableSubtitleTracks.isEmpty {
                            Divider().background(Color.white.opacity(0.1)).padding(.vertical, 4)

                            ForEach(viewModel.availableSubtitleTracks) { embeddedTrack in
                                trackRow(
                                    id: "stream_\(embeddedTrack.id)",
                                    name: "\(embeddedTrack.displayName) [Stream]",
                                    isSelected: viewModel.selectedSubtitleTrackId == embeddedTrack.id && viewModel.selectedExternalSubtitle == nil
                                ) {
                                    Task {
                                        await viewModel.selectExternalSubtitleTrack(nil)
                                        viewModel.selectSubtitleTrack(embeddedTrack.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: 380)
            }
            .frame(width: 490)
            .background(Color.auraSurface.opacity(0.94), in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.65), radius: 24, y: 10)
            .padding(.trailing, 70)
            .padding(.bottom, 190)
        }
    }

    // MARK: - Audio Picker Popover

    @ViewBuilder
    private var audioPickerOverlay: some View {
        VStack(alignment: .trailing) {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                Text("Audio Tracks")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                Divider().background(Color.white.opacity(0.14))

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(viewModel.availableAudioTracks) { track in
                            trackRow(
                                id: "audio_\(track.id)",
                                name: track.displayName,
                                isSelected: viewModel.selectedAudioTrackId == track.id
                            ) {
                                viewModel.selectAudioTrack(track.id)
                            }
                        }

                        if viewModel.availableAudioTracks.isEmpty {
                            Text("No alternate audio tracks detected")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(20)
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 280)
            }
            .frame(width: 420)
            .background(Color.auraSurface.opacity(0.94), in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.65), radius: 24, y: 10)
            .padding(.trailing, 70)
            .padding(.bottom, 190)
        }
    }

    // MARK: - Stream & Media Info Popover

    @ViewBuilder
    private var infoPanelOverlay: some View {
        VStack(alignment: .trailing) {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Playback & Stream Info")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    BadgeView(text: viewModel.selectedStream?.parsedInfo.resolution.displayName ?? "4K", style: .filled, fontSize: 12)
                }

                Divider().background(Color.white.opacity(0.12))

                infoItem(label: "Title", value: viewModel.title)

                if let provider = viewModel.selectedStream?.parsedInfo.providerName {
                    infoItem(label: "Provider", value: provider)
                }
                if let size = viewModel.selectedStream?.parsedInfo.fileSize {
                    infoItem(label: "File Size", value: size)
                }
                if let audio = viewModel.selectedStream?.parsedInfo.audioCodec {
                    infoItem(label: "Audio Codec", value: audio)
                }
                if let sub = viewModel.selectedExternalSubtitle {
                    infoItem(label: "Active Subtitle", value: sub.displayName)
                }
                if !viewModel.overview.isEmpty {
                    Text(viewModel.overview)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(3)
                        .padding(.top, 4)
                }
            }
            .padding(24)
            .frame(width: 460)
            .background(Color.auraSurface.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.65), radius: 24, y: 10)
            .padding(.trailing, 70)
            .padding(.bottom, 190)
        }
    }

    private func infoItem(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
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
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedTrackId, equals: id)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
