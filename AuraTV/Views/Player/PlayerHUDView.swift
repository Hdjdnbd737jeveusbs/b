import SwiftUI

// MARK: - Player HUD View (Clean Cinema HUD — Reference-Matching)

struct PlayerHUDView: View {
    @Bindable var viewModel: PlayerViewModel

    @State private var isSearchFieldActive: Bool = false
    @FocusState private var focusedControl: HUDControl?
    @FocusState private var focusedTrackId: String?

    enum HUDControl: Hashable {
        case timeline
        case subtitles
        case subtitleStyle
        case audio
        case chapters
        case info
        case skipIntro
        case playNext
        case dismissUpNext
    }

    var body: some View {
        ZStack {
            // Top bar: Clean White Title Logo ONLY (No tech badges)
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
                .padding(.bottom, 165)
            }

            // Bottom: 5 icon buttons + scrubber + elapsed under thumb & remaining right
            VStack {
                Spacer()
                bottomBar
            }

            // Right-anchored Subtitles popover
            if viewModel.showSubtitlePicker {
                subtitlePickerOverlay
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Right-anchored Audio popover
            if viewModel.showAudioPicker {
                audioPickerOverlay
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Right-anchored Playback Options popover
            if viewModel.showOptionsMenu {
                optionsMenuOverlay
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Right-anchored Info popover
            if viewModel.showInfoPanel {
                infoPanelOverlay
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .defaultFocus($focusedControl, .subtitles)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if viewModel.showSubtitlePicker {
                    focusedTrackId = "encoding_action"
                } else if focusedControl == nil {
                    focusedControl = .subtitles
                }
            }
        }
        .onChange(of: viewModel.showSubtitlePicker) { _, isOpen in
            if isOpen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    focusedTrackId = viewModel.selectedExternalSubtitle?.id ?? "off"
                }
            } else {
                isSearchFieldActive = false
                focusedControl = .subtitles
            }
        }
        .onChange(of: viewModel.showOptionsMenu) { _, isOpen in
            if isOpen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    focusedTrackId = "opt_aspect"
                }
            } else {
                focusedControl = .chapters
            }
        }
        .onChange(of: viewModel.showInfoPanel) { _, isOpen in
            if isOpen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    focusedTrackId = "info_toggle_stats"
                }
            } else {
                focusedControl = .info
            }
        }
        .onTapGesture {
            viewModel.toggleHUD()
        }
    }

    // MARK: - Top Bar (Clean White Title Logo Only)

    @ViewBuilder
    private var topBar: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                gradient: Gradient(colors: [Color.auraBackground.opacity(0.88), .clear]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 150)

            VStack(alignment: .leading, spacing: 6) {
                if viewModel.tmdbId > 0 {
                    TitleLogoView(
                        title: viewModel.title,
                        mediaType: viewModel.mediaType,
                        tmdbId: viewModel.tmdbId,
                        maxWidth: 340,
                        maxHeight: 54,
                        fallbackFontSize: 28,
                        alignment: .leading
                    )
                } else {
                    Text(viewModel.title.uppercased())
                        .font(.system(size: 28, weight: .bold))
                        .tracking(8)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.75), radius: 8, x: 0, y: 2)
                }

                if viewModel.mediaType == "series",
                   let season = viewModel.seasonNumber,
                   let episode = viewModel.episodeNumber {
                    HStack(spacing: 8) {
                        Text("S\(season) • E\(episode)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))

                        if let epTitle = viewModel.episodeTitle, !epTitle.isEmpty {
                            Text("-")
                                .foregroundStyle(.white.opacity(0.5))
                            Text(epTitle)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 70)
            .padding(.top, 46)
        }
    }

    // MARK: - Bottom Bar (5 Icon Buttons + Slim Scrubber + Thumb-Aligned Time Labels)

    @ViewBuilder
    private var bottomBar: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                gradient: Gradient(colors: [.clear, Color.auraBackground.opacity(0.92)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 165)

            VStack(spacing: 0) {
                // 5 icon-only buttons aligned above the right side of the scrubber
                HStack {
                    Spacer()
                    HStack(spacing: 14) {
                        hudIconButton(
                            icon: focusedControl == .subtitles ? "captions.bubble.fill" : "captions.bubble",
                            control: .subtitles
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                viewModel.showSubtitlePicker.toggle()
                                viewModel.showAudioPicker = false
                                viewModel.showOptionsMenu = false
                                viewModel.showInfoPanel = false
                            }
                        }

                        hudIconButton(
                            textLabel: "Aa",
                            control: .subtitleStyle
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                viewModel.showSubtitleStyleSheet = true
                                viewModel.showSubtitlePicker = false
                                viewModel.showAudioPicker = false
                                viewModel.showOptionsMenu = false
                                viewModel.showInfoPanel = false
                            }
                        }

                        hudIconButton(
                            icon: "waveform",
                            control: .audio
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                viewModel.showAudioPicker.toggle()
                                viewModel.showSubtitlePicker = false
                                viewModel.showOptionsMenu = false
                                viewModel.showInfoPanel = false
                            }
                        }

                        hudIconButton(
                            icon: "list.bullet.rectangle",
                            control: .chapters
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                viewModel.showOptionsMenu.toggle()
                                viewModel.showSubtitlePicker = false
                                viewModel.showAudioPicker = false
                                viewModel.showInfoPanel = false
                            }
                        }

                        hudIconButton(
                            icon: "info.circle",
                            control: .info
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                viewModel.showInfoPanel.toggle()
                                viewModel.showSubtitlePicker = false
                                viewModel.showAudioPicker = false
                                viewModel.showOptionsMenu = false
                            }
                        }
                    }
                }
                .padding(.bottom, 12)

                // Full-width slim scrubber
                timelineBar

                // Elapsed time under thumb + remaining time flush right
                GeometryReader { geo in
                    let totalWidth = geo.size.width
                    let thumbCenterX = totalWidth * viewModel.progress
                    let elapsedX = min(max(0, thumbCenterX - 24), max(0, totalWidth - 180))

                    ZStack(alignment: .leading) {
                        HStack {
                            Spacer()
                            Text(viewModel.remainingTimeFormatted)
                                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.92))
                        }

                        Text(viewModel.currentTimeFormatted)
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.92))
                            .offset(x: elapsedX)
                    }
                }
                .frame(height: 24)
                .padding(.top, 8)
            }
            .padding(.horizontal, 70)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Timeline Scrubber

    @ViewBuilder
    private var timelineBar: some View {
        let isFocused = focusedControl == .timeline

        GeometryReader { geometry in
            let width = geometry.size.width
            let thumbX = max(0, (width * viewModel.progress) - (isFocused ? 3 : 1.5))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.26))
                    .frame(height: isFocused ? 8 : 4)

                Capsule()
                    .fill(Color.white)
                    .frame(width: width * viewModel.progress, height: isFocused ? 8 : 4)

                // Slim vertical playhead tick matching reference scrubber
                Capsule()
                    .fill(Color.white)
                    .frame(width: isFocused ? 6 : 3, height: isFocused ? 20 : 12)
                    .shadow(color: .black.opacity(0.6), radius: 4)
                    .offset(x: thumbX)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.16), value: isFocused)
        }
        .frame(height: 20)
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

    // MARK: - HUD Icon Button (Minimal — Solid White Circle on Focus Only)

    @ViewBuilder
    private func hudIconButton(
        icon: String? = nil,
        textLabel: String? = nil,
        control: HUDControl,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focusedControl == control
        let size: CGFloat = 44

        Button(action: action) {
            Group {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .medium))
                } else if let textLabel {
                    Text(textLabel)
                        .font(.system(size: 19, weight: .semibold))
                }
            }
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(isFocused ? Color.white : Color.clear)
            )
            .scaleEffect(isFocused ? 1.1 : 1.0)
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
            .background(isFocused ? Color.white : Color.auraCardSurface, in: Capsule())
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

    // MARK: - Subtitle Picker Popover (Right-Anchored)

    @ViewBuilder
    private var subtitlePickerOverlay: some View {
        VStack(alignment: .trailing) {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Top: Search Subtitles row (white pill only when focused)
                        if isSearchFieldActive {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                TextField("Search Subtitles...", text: $viewModel.subtitleSearchText)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        } else {
                            let isSearchFocused = focusedTrackId == "search_subs"
                            Button {
                                isSearchFieldActive = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(isSearchFocused ? Color.black : Color.white.opacity(0.9))
                                        .frame(width: 18)

                                    Text("Search Subtitles...")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(isSearchFocused ? Color.black : Color.white)

                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(isSearchFocused ? Color.white : Color.clear)
                                )
                            }
                            .buttonStyle(AuraButtonStyle())
                            .focusEffectDisabled()
                            .focused($focusedTrackId, equals: "search_subs")
                        }

                        // Off row
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
                                Text("Searching subtitles...")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.auraSecondaryText)
                            }
                            .padding(14)
                        } else {
                            ForEach(viewModel.filteredSubtitleTracks) { track in
                                trackRow(
                                    id: track.id,
                                    name: subtitleRowLabel(for: track),
                                    isSelected: viewModel.selectedExternalSubtitle?.id == track.id
                                ) {
                                    Task {
                                        await viewModel.selectExternalSubtitleTrack(track)
                                    }
                                }
                            }
                        }

                        if !viewModel.availableSubtitleTracks.isEmpty {
                            ForEach(viewModel.availableSubtitleTracks) { embeddedTrack in
                                trackRow(
                                    id: "stream_\(embeddedTrack.id)",
                                    name: embeddedTrack.displayName,
                                    isSelected: viewModel.selectedSubtitleTrackId == embeddedTrack.id && viewModel.selectedExternalSubtitle == nil
                                ) {
                                    Task {
                                        await viewModel.selectExternalSubtitleTrack(nil)
                                        viewModel.selectSubtitleTrack(embeddedTrack.id)
                                    }
                                }
                            }
                        }

                        // Bottom actions: Subtitle Sync... & Text Encoding >
                        let syncFocused = focusedTrackId == "sync_action"
                        Button {
                            viewModel.showSubtitleSyncSheet = true
                            viewModel.showSubtitlePicker = false
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(syncFocused ? Color.black : Color.white.opacity(0.9))
                                    .frame(width: 18)

                                Text("Subtitle Sync...")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(syncFocused ? Color.black : Color.white)

                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(syncFocused ? Color.white : Color.clear)
                            )
                        }
                        .buttonStyle(AuraButtonStyle())
                        .focusEffectDisabled()
                        .focused($focusedTrackId, equals: "sync_action")

                        let syncLineFocused = focusedTrackId == "sync_to_line_action"
                        Button {
                            viewModel.showSyncToLineSheet = true
                            viewModel.showSubtitlePicker = false
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(syncLineFocused ? Color.black : Color.white.opacity(0.9))
                                    .frame(width: 18)

                                Text("Sync to a Line...")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(syncLineFocused ? Color.black : Color.white)

                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(syncLineFocused ? Color.white : Color.clear)
                            )
                        }
                        .buttonStyle(AuraButtonStyle())
                        .focusEffectDisabled()
                        .focused($focusedTrackId, equals: "sync_to_line_action")

                        let encodingFocused = focusedTrackId == "encoding_action"
                        Button {
                            viewModel.showSubtitleStyleSheet = true
                            viewModel.showSubtitlePicker = false
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(encodingFocused ? Color.black : Color.white.opacity(0.9))
                                    .frame(width: 18)

                                Text("Text Encoding")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(encodingFocused ? Color.black : Color.white)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(encodingFocused ? Color.black.opacity(0.65) : Color.white.opacity(0.55))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(encodingFocused ? Color.white : Color.clear)
                            )
                        }
                        .buttonStyle(AuraButtonStyle())
                        .focusEffectDisabled()
                        .focused($focusedTrackId, equals: "encoding_action")
                    }
                    .padding(10)
                }
                .frame(maxHeight: 520)
            }
            .frame(width: 440)
            .background(Color(red: 22 / 255, green: 24 / 255, blue: 30 / 255).opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.65), radius: 24, y: 10)
            .padding(.trailing, 70)
            .padding(.bottom, 145)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func subtitleRowLabel(for track: SubtitleTrackItem) -> String {
        if let rel = track.releaseInfo, !rel.isEmpty {
            return "\(track.language) · \(rel)"
        }
        return track.displayName
    }

    // MARK: - Audio Picker Popover

    @ViewBuilder
    private var audioPickerOverlay: some View {
        VStack(alignment: .trailing) {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                Text("Audio Tracks")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

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
            .background(Color(red: 22 / 255, green: 24 / 255, blue: 30 / 255).opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.65), radius: 24, y: 10)
            .padding(.trailing, 70)
            .padding(.bottom, 145)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    // MARK: - Playback Options Popover (Right-Anchored)

    @ViewBuilder
    private var optionsMenuOverlay: some View {
        VStack(alignment: .trailing) {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                Text("Playback Options")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                Divider().background(Color.white.opacity(0.14))

                VStack(spacing: 4) {
                    optionCycleRow(
                        id: "opt_aspect",
                        icon: "aspectratio",
                        title: "Aspect Ratio",
                        value: viewModel.aspectRatioMode.rawValue
                    ) {
                        viewModel.cycleAspectRatio()
                    }

                    optionCycleRow(
                        id: "opt_speed",
                        icon: "gauge.with.dots.needle.67percent",
                        title: "Playback Speed",
                        value: viewModel.speedDisplayText
                    ) {
                        viewModel.cyclePlaybackSpeed()
                    }

                    optionCycleRow(
                        id: "opt_sleep",
                        icon: "moon.zzz",
                        title: "Sleep Timer",
                        value: viewModel.sleepTimerDisplayText
                    ) {
                        viewModel.cycleSleepTimer()
                    }

                    optionCycleRow(
                        id: "opt_stats",
                        icon: "chart.bar.xaxis",
                        title: "Live Playback Stats",
                        value: viewModel.showLiveStatsHUD ? "On" : "Off"
                    ) {
                        viewModel.showLiveStatsHUD.toggle()
                    }

                    if !viewModel.availableStreams.isEmpty {
                        optionCycleRow(
                            id: "opt_streams",
                            icon: "rectangle.stack",
                            title: "Stream Sources...",
                            value: viewModel.selectedStream?.parsedInfo.resolution.displayName ?? "Switch"
                        ) {
                            viewModel.showOptionsMenu = false
                            viewModel.showStreamPicker = true
                        }
                    }
                }
                .padding(10)
            }
            .frame(width: 420)
            .background(Color(red: 22 / 255, green: 24 / 255, blue: 30 / 255).opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.65), radius: 24, y: 10)
            .padding(.trailing, 70)
            .padding(.bottom, 145)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    @ViewBuilder
    private func optionCycleRow(
        id: String,
        icon: String,
        title: String,
        value: String,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focusedTrackId == id

        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isFocused ? Color.black : Color.white.opacity(0.85))
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isFocused ? Color.black : Color.white)

                Spacer()

                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isFocused ? Color.black.opacity(0.75) : Color.white.opacity(0.65))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isFocused ? Color.white : Color.clear)
            )
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedTrackId, equals: id)
        .scaleEffect(isFocused ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.14), value: isFocused)
    }

    // MARK: - Stream & Media Info Popover

    @ViewBuilder
    private var infoPanelOverlay: some View {
        VStack(alignment: .trailing) {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Playback & Stream Info")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    BadgeView(text: viewModel.selectedStream?.parsedInfo.resolution.displayName ?? viewModel.playbackStats.resolution, style: .filled, fontSize: 12)
                }

                Divider().background(Color.white.opacity(0.12))

                infoItem(label: "Title", value: viewModel.title)
                infoItem(label: "Engine", value: viewModel.playbackStats.activeEngine)
                infoItem(label: "Dynamic Range", value: viewModel.playbackStats.dynamicRange)

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

                Divider().background(Color.white.opacity(0.12))

                optionCycleRow(
                    id: "info_toggle_stats",
                    icon: "chart.bar.xaxis",
                    title: viewModel.showLiveStatsHUD ? "Hide Live Stats HUD" : "Show Live Stats HUD",
                    value: viewModel.showLiveStatsHUD ? "On" : "Off"
                ) {
                    viewModel.showLiveStatsHUD.toggle()
                }
            }
            .padding(22)
            .frame(width: 440)
            .background(Color(red: 22 / 255, green: 24 / 255, blue: 30 / 255).opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.65), radius: 24, y: 10)
            .padding(.trailing, 70)
            .padding(.bottom, 145)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
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

    // MARK: - Track Row (Checkmark on Active, White Pill ONLY on Focus)

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
                    .foregroundStyle(isFocused ? Color.black : Color.white.opacity(0.92))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isFocused ? Color.white : Color.clear)
            )
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedTrackId, equals: id)
        .scaleEffect(isFocused ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}
