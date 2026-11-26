import SwiftUI
import SwiftData

// MARK: - Movie Detail View (Full-Bleed Backdrop + TMDB Logo + Action Pill Bar)

struct MovieDetailView: View {
    let tmdbId: Int

    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @Query private var artworkOverrides: [CustomArtwork]
    @State private var viewModel = DetailViewModel()
    @FocusState private var focusedButton: DetailButton?

    // Streaming & Subtitles state
    @State private var showStreamPicker = false
    @State private var showPlayer = false
    @State private var showMoreOptions = false
    @State private var showChangeArtwork = false
    @State private var availableStreams: [StremioStream] = []
    @State private var selectedStream: StremioStream?
    @State private var isLoadingStreams = false
    @State private var streamError: String?
    @State private var playerViewModel = PlayerViewModel()
    @State private var movieImdbId: String?

    private var customArtwork: CustomArtwork? {
        let key = CustomArtwork.makeKey(tmdbId: tmdbId, mediaType: "movie")
        return artworkOverrides.first { $0.key == key }
    }

    private var effectivePosterPath: String? {
        customArtwork?.customPosterPath ?? viewModel.movieDetail?.posterPath
    }

    private var effectiveBackdropPath: String? {
        customArtwork?.customBackdropPath ?? viewModel.movieDetail?.backdropPath ?? effectivePosterPath
    }

    private var effectiveLogoPath: String? {
        customArtwork?.customLogoPath ?? viewModel.logoPath
    }

    private var preferredQuality: String {
        settingsList.first?.preferredQuality ?? "4K"
    }

    private var effectiveResumeTime: Double {
        let settings = settingsList.first
        return ExternalPlayerService.adjustedResumeTime(
            rawTime: viewModel.watchProgress?.currentTime ?? 0,
            behavior: settings?.resumePlaybackBehavior ?? "Ask",
            rewindSeconds: settings?.rewindOnResumeSeconds ?? 5
        )
    }

    enum DetailButton: Hashable {
        case play
        case rewatch
        case watched
        case artwork
        case more
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.auraBackground.ignoresSafeArea()

                // Full-bleed dark cinema backdrop + left & bottom vignettes
                backdropLayer(geometry: geometry)

                // Scrollable foreground content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 36) {
                        // Left hero metadata column
                        VStack(alignment: .leading, spacing: 18) {
                            Spacer().frame(height: geometry.size.height * 0.14)

                            titleSection

                            metadataLine

                            technicalBadgesRow

                            overviewSection

                            actionButtons
                                .padding(.top, 6)
                        }
                        .frame(maxWidth: geometry.size.width * 0.54, alignment: .leading)
                        .padding(.leading, 80)

                        // Full-width circular Cast row below the fold
                        castSection

                        Spacer().frame(height: 60)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .task {
            await viewModel.loadMovieDetail(id: tmdbId, context: modelContext)
        }
        .sheet(isPresented: $showStreamPicker) {
            StreamPickerSheet(
                title: viewModel.movieDetail?.title ?? "Movie",
                streams: availableStreams,
                selectedStream: selectedStream,
                preferredQuality: preferredQuality,
                onSelect: { stream in
                    selectedStream = stream
                    if let urlString = stream.url, let url = URL(string: urlString) {
                        startPlayback(url: url, stream: stream, resumeFrom: effectiveResumeTime)
                    }
                },
                onDismiss: { showStreamPicker = false }
            )
        }
        .sheet(isPresented: $showChangeArtwork) {
            ChangeArtworkView(
                tmdbId: tmdbId,
                mediaType: "movie",
                title: viewModel.movieDetail?.title ?? "Movie",
                defaultPosterPath: viewModel.movieDetail?.posterPath,
                defaultBackdropPath: viewModel.movieDetail?.backdropPath,
                defaultLogoPath: viewModel.logoPath
            )
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView(viewModel: playerViewModel)
        }
        .confirmationDialog("Options", isPresented: $showMoreOptions, titleVisibility: .visible) {
            Button("Choose Stream Source...") {
                playMovie(forcePicker: true)
            }
            Button(viewModel.isInWatchlist ? "Remove from Watchlist" : "Add to Watchlist") {
                viewModel.toggleWatchlist(
                    tmdbId: tmdbId,
                    mediaType: "movie",
                    title: viewModel.movieDetail?.title ?? "",
                    posterPath: effectivePosterPath,
                    backdropPath: effectiveBackdropPath,
                    context: modelContext
                )
            }
            Button("Change Artwork...") {
                showChangeArtwork = true
            }
            Button(viewModel.isWatched ? "Mark as Unwatched" : "Mark as Watched") {
                viewModel.toggleWatched(
                    tmdbId: tmdbId,
                    mediaType: "movie",
                    title: viewModel.movieDetail?.title ?? "",
                    posterPath: effectivePosterPath,
                    backdropPath: effectiveBackdropPath,
                    context: modelContext
                )
            }
            Button("Cancel", role: .cancel) {}
        }
        .overlay {
            if isLoadingStreams {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Finding streams...")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .alert("Stream Error", isPresented: .init(
            get: { streamError != nil },
            set: { if !$0 { streamError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(streamError ?? "Unknown error")
        }
    }

    // MARK: - Backdrop Layer with Cinematic Vignettes

    @ViewBuilder
    private func backdropLayer(geometry: GeometryProxy) -> some View {
        let height = geometry.size.height * 0.78
        ZStack(alignment: .topTrailing) {
            if let path = effectiveBackdropPath,
               let url = TMDBService.shared.imageURL(path: path, size: "original") {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width * 0.78, height: height)
                            .clipped()
                    case .failure, .empty:
                        backdropPlaceholder(width: geometry.size.width * 0.78, height: height)
                    @unknown default:
                        backdropPlaceholder(width: geometry.size.width * 0.78, height: height)
                    }
                }
            } else {
                backdropPlaceholder(width: geometry.size.width * 0.78, height: height)
            }
        }
        .frame(width: geometry.size.width, height: height, alignment: .topTrailing)
        .overlay {
            // Left horizontal fade into #090B10
            LinearGradient(
                stops: [
                    .init(color: Color.auraBackground, location: 0.0),
                    .init(color: Color.auraBackground.opacity(0.95), location: 0.24),
                    .init(color: Color.auraBackground.opacity(0.68), location: 0.45),
                    .init(color: .clear, location: 0.85)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .overlay {
            // Bottom vertical vignette into #090B10
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.45),
                    .init(color: Color.auraBackground.opacity(0.75), location: 0.80),
                    .init(color: Color.auraBackground, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private func backdropPlaceholder(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.auraSurface)
            .frame(width: width, height: height)
    }

    // MARK: - Title Logo

    @ViewBuilder
    private var titleSection: some View {
        if let detail = viewModel.movieDetail {
            TitleLogoView(
                title: detail.title,
                mediaType: "movie",
                tmdbId: detail.id,
                preloadedLogoPath: effectiveLogoPath,
                maxWidth: 560,
                maxHeight: 145,
                fallbackFontSize: 58,
                alignment: .leading
            )
        } else {
            ProgressView()
                .tint(.white)
        }
    }

    // MARK: - Metadata Line (Year • Rating • Runtime • Genres)

    @ViewBuilder
    private var metadataLine: some View {
        if let detail = viewModel.movieDetail {
            HStack(spacing: 10) {
                if let date = detail.releaseDate, date.count >= 4 {
                    Text(String(date.prefix(4)))
                }

                if let cert = viewModel.certification, !cert.isEmpty {
                    Text("•")
                        .foregroundStyle(.white.opacity(0.5))
                    Text(cert)
                }

                if let runtime = detail.runtime, runtime > 0 {
                    Text("•")
                        .foregroundStyle(.white.opacity(0.5))
                    Text(formatRuntime(runtime))
                }

                if let genres = detail.genres, !genres.isEmpty {
                    Text("•")
                        .foregroundStyle(.white.opacity(0.5))
                    Text(genres.map(\.name).prefix(2).joined(separator: ", "))
                        .lineLimit(1)
                }
            }
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(.white.opacity(0.76))
        }
    }

    // MARK: - Solid 4K + Dolby Vision + Outlined Technical Badges + Score

    @ViewBuilder
    private var technicalBadgesRow: some View {
        HStack(spacing: 8) {
            BadgeView(text: "4K", style: .filled, fontSize: 12)
            DolbyVisionBadgeView()
            BadgeView(text: "5.1", style: .outlined, fontSize: 12)
            BadgeView(text: "CC", style: .outlined, fontSize: 12)
            BadgeView(text: "SDH", style: .outlined, fontSize: 12)
            BadgeView(text: "AR", style: .outlined, fontSize: 12)

            if let vote = viewModel.movieDetail?.voteAverage, vote > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.white.opacity(0.65))
                        .font(.system(size: 13))
                    Text(String(format: "%.1f", vote))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.leading, 4)
            }
        }
    }

    // MARK: - 3-Line Synopsis

    @ViewBuilder
    private var overviewSection: some View {
        if let overview = viewModel.movieDetail?.overview, !overview.isEmpty {
            Text(overview)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(3)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Action Buttons Row

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 14) {
            // Primary Solid White Pill Button with inline mini progress bar on resume
            Button(action: { playMovie() }) {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 17))

                    if let progress = viewModel.watchProgress,
                       progress.progress > 0 && !progress.isCompleted,
                       !progress.remainingTimeFormatted.isEmpty {
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.black.opacity(0.22))
                                .frame(width: 46, height: 4)
                            Capsule()
                                .fill(Color.black.opacity(0.88))
                                .frame(width: max(8, 46 * min(max(progress.progress, 0), 1)), height: 4)
                        }

                        Text(progress.remainingTimeFormatted)
                            .font(.system(size: 19, weight: .bold))
                    } else {
                        Text("Play")
                            .font(.system(size: 19, weight: .bold))
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(Color.white)
                .foregroundStyle(.black)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(focusedButton == .play ? Color.white : .clear, lineWidth: 3)
                        .padding(-4)
                )
            }
            .buttonStyle(AuraButtonStyle())
            .focusEffectDisabled()
            .focused($focusedButton, equals: .play)
            .scaleEffect(focusedButton == .play ? 1.07 : 1.0)
            .animation(.easeOut(duration: 0.18), value: focusedButton)

            // Rewatch glass pill if currently resuming
            if let progress = viewModel.watchProgress, progress.progress > 0 && !progress.isCompleted {
                Button(action: { rewatchMovie() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Rewatch")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(focusedButton == .rewatch ? Color.white : Color.white.opacity(0.14))
                    .foregroundStyle(focusedButton == .rewatch ? .black : .white)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                }
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()
                .focused($focusedButton, equals: .rewatch)
                .scaleEffect(focusedButton == .rewatch ? 1.07 : 1.0)
                .animation(.easeOut(duration: 0.18), value: focusedButton)
            }

            // Watched Toggle Circular Glass Button
            circleGlassButton(
                systemName: "checkmark",
                isActive: viewModel.isWatched,
                target: .watched
            ) {
                viewModel.toggleWatched(
                    tmdbId: tmdbId,
                    mediaType: "movie",
                    title: viewModel.movieDetail?.title ?? "",
                    posterPath: effectivePosterPath,
                    backdropPath: effectiveBackdropPath,
                    context: modelContext
                )
            }

            // Change Artwork Circular Glass Button
            circleGlassButton(
                systemName: "paintpalette",
                isActive: customArtwork != nil,
                target: .artwork
            ) {
                showChangeArtwork = true
            }

            // More (...) Circular Glass Button
            circleGlassButton(
                systemName: "ellipsis",
                isActive: false,
                target: .more
            ) {
                showMoreOptions = true
            }
        }
    }

    @ViewBuilder
    private func circleGlassButton(
        systemName: String,
        isActive: Bool,
        target: DetailButton,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focusedButton == target
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 52, height: 52)
                .background(isFocused ? Color.white : (isActive ? Color.white.opacity(0.28) : Color.white.opacity(0.14)))
                .foregroundStyle(isFocused ? Color.black : Color.white)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedButton, equals: target)
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .animation(.easeOut(duration: 0.18), value: focusedButton)
    }

    // MARK: - Cast Section (Full-Width Horizontal Row of Circular Portraits)

    @ViewBuilder
    private var castSection: some View {
        if !viewModel.cast.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Cast")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 20) {
                        ForEach(viewModel.cast.prefix(20)) { member in
                            CastCardView(member: member)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Helpers & Playback

    private func formatRuntime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }

    private func playMovie(forcePicker: Bool = false) {
        Task {
            isLoadingStreams = true
            streamError = nil
            do {
                if movieImdbId == nil {
                    let ext = try? await TMDBService.shared.fetchMovieExternalIds(id: tmdbId)
                    movieImdbId = ext?.imdbId
                }
                let streams = try await AIOStreamsService.shared.fetchStreamsForMovie(
                    tmdbId: tmdbId,
                    preferredQuality: preferredQuality
                )
                availableStreams = streams
                let best = AIOStreamsService.shared.bestStream(matching: preferredQuality, in: streams)
                selectedStream = best
                isLoadingStreams = false

                if !forcePicker && streams.count == 1, let single = streams.first, let url = URL(string: single.url ?? "") {
                    startPlayback(url: url, stream: single, resumeFrom: effectiveResumeTime)
                } else {
                    showStreamPicker = true
                }
            } catch {
                isLoadingStreams = false
                streamError = error.localizedDescription
            }
        }
    }

    private func rewatchMovie() {
        if let progress = viewModel.watchProgress {
            progress.currentTime = 0
            progress.isCompleted = false
            try? modelContext.save()
        }
        playMovie()
    }

    private func startPlayback(url: URL, stream: StremioStream? = nil, resumeFrom: Double = 0) {
        let detail = viewModel.movieDetail
        let movieTitle = detail?.title ?? "Movie"
        let externalName = settingsList.first?.externalPlayer ?? "Built-in AetherEngine"

        ExternalPlayerService.openExternalPlayerIfConfigured(
            playerName: externalName,
            streamURL: url,
            title: movieTitle
        ) { openedExternally in
            if openedExternally {
                showStreamPicker = false
                return
            }

            playerViewModel = PlayerViewModel()
            playerViewModel.configure(
                url: url,
                title: movieTitle,
                overview: detail?.overview ?? "",
                backdropPath: effectiveBackdropPath,
                posterPath: effectivePosterPath,
                tmdbId: tmdbId,
                mediaType: "movie",
                resumeFrom: resumeFrom,
                imdbId: movieImdbId ?? "",
                availableStreams: availableStreams,
                selectedStream: stream ?? selectedStream
            )
            showStreamPicker = false
            showPlayer = true
        }
    }
}
