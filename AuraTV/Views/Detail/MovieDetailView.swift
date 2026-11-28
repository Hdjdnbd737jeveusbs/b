import SwiftUI
import SwiftData

// MARK: - Movie Detail View (Full-Bleed Backdrop + TMDB Logo + Action Pill Bar)

struct MovieDetailView: View {
    let tmdbId: Int
    var autoPlayOnAppear: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]
    @Query private var artworkOverrides: [CustomArtwork]
    @State private var viewModel = DetailViewModel()
    @State private var detailToken = UUID()
    @State private var didTriggerAutoPlay = false
    @State private var prefetchTask: Task<Void, Never>?

    // Streaming & Subtitles state
    @State private var showStreamPicker = false
    @State private var showPlayer = false
    @State private var showMoreOptions = false
    @State private var showChangeArtwork = false
    @State private var availableStreams: [StremioStream] = []
    @State private var selectedStream: StremioStream?
    @State private var isLoadingStreams = false
    @State private var isLoadingMoreStreams = false
    @State private var activeStreamFetchTask: Task<Void, Never>?
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

    private var playAtOnceEnabled: Bool {
        settingsList.first?.playAtOnce ?? false
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
                Color.black.ignoresSafeArea()

                // Full-bleed dark cinema backdrop fading seamlessly into #000000 black
                backdropLayer(geometry: geometry)

                // Scrollable foreground content
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Left hero metadata column (aligned at leading: 80pt)
                        VStack(alignment: .leading, spacing: 18) {
                            Spacer().frame(height: 120)

                            titleSection

                            metadataLine

                            technicalBadgesRow

                            if let ratings = viewModel.mdblistRatings, !ratings.isEmpty {
                                MDBListRatingsRow(ratings: ratings)
                            }

                            overviewSection

                            actionButtons
                                .padding(.top, 8)
                        }
                        .frame(maxWidth: geometry.size.width * 0.60, minHeight: geometry.size.height * 0.85, alignment: .topLeading)
                        .padding(.leading, 80)
                        .focusSection()

                        // Cast section pinned near bottom of initial viewport
                        castSection
                            .padding(.top, 16)
                            .focusSection()

                        Spacer().frame(height: 60)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            AuraNavigationMemory.shared.pushDetail(id: detailToken) { dismiss() }
        }
        .onDisappear {
            AuraNavigationMemory.shared.popDetail(id: detailToken)
            prefetchTask?.cancel()
            activeStreamFetchTask?.cancel()
            viewModel.stopPrefetchingDetailAssets(
                backdropPath: effectiveBackdropPath,
                cast: viewModel.cast
            )
        }
        .task {
            let quality = preferredQuality
            prefetchTask?.cancel()
            prefetchTask = Task { @MainActor in
                let streams = await Task.detached(priority: .utility) { [tmdbId] in
                    await AIOStreamsService.shared.prefetchStreamsForMovie(
                        tmdbId: tmdbId,
                        preferredQuality: quality
                    )
                }.value
                if !Task.isCancelled && availableStreams.isEmpty && !streams.isEmpty {
                    availableStreams = streams
                }
            }

            await viewModel.loadMovieDetail(id: tmdbId, context: modelContext)
            AppThemeCoordinator.shared.updateFocusedArtwork(
                posterPath: effectivePosterPath,
                backdropPath: effectiveBackdropPath
            )
            if autoPlayOnAppear && !didTriggerAutoPlay {
                didTriggerAutoPlay = true
                playMovie()
            }
        }
        .onChange(of: showPlayer) { _, isPresented in
            if !isPresented {
                viewModel.loadWatchProgress(tmdbId: tmdbId, mediaType: "movie", context: modelContext)
            }
        }
        .sheet(isPresented: $showStreamPicker) {
            StreamPickerSheet(
                title: viewModel.movieDetail?.title ?? "Movie",
                streams: availableStreams,
                selectedStream: selectedStream,
                preferredQuality: preferredQuality,
                isLoadingMore: isLoadingMoreStreams,
                onSelect: { stream in
                    activeStreamFetchTask?.cancel()
                    isLoadingMoreStreams = false
                    selectedStream = stream
                    if let urlString = stream.url, let url = URL(string: urlString) {
                        startPlayback(url: url, stream: stream, resumeFrom: effectiveResumeTime)
                    }
                },
                onDismiss: {
                    activeStreamFetchTask?.cancel()
                    isLoadingStreams = false
                    isLoadingMoreStreams = false
                    showStreamPicker = false
                }
            )
        }
        .fullScreenCover(isPresented: $showChangeArtwork) {
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
        let width = geometry.size.width
        let height = geometry.size.height * 0.88
        ZStack(alignment: .top) {
            if let path = effectiveBackdropPath,
               let url = TMDBService.shared.imageURL(path: path, size: "w1280") {
                AuraCachedImage(url: url, targetSize: CGSize(width: 1920, height: 950)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipped()
                } placeholder: {
                    backdropPlaceholder(width: width, height: height)
                }
            } else {
                backdropPlaceholder(width: width, height: height)
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .overlay(
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.84), location: 0.0),
                    .init(color: Color.black.opacity(0.42), location: 0.44),
                    .init(color: .clear, location: 0.82)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.45),
                    .init(color: Color.black.opacity(0.55), location: 0.78),
                    .init(color: Color.black, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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
                maxWidth: 580,
                maxHeight: 140,
                fallbackFontSize: 58,
                alignment: .leading
            )
        } else {
            ProgressView()
                .tint(.white)
        }
    }

    // MARK: - Metadata Line (Year · Rating · Runtime · Genres)

    @ViewBuilder
    private var metadataLine: some View {
        if let detail = viewModel.movieDetail {
            let year = detail.releaseDate.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil }
            let cert = viewModel.certification.flatMap { $0.isEmpty ? nil : $0 }
            let runtime = detail.runtime.flatMap { $0 > 0 ? formatRuntime($0) : nil }
            let genres = detail.genres.flatMap {
                let joined = $0.map(\.name).prefix(2).joined(separator: ", ")
                return joined.isEmpty ? nil : joined
            }
            let text = [year, cert, runtime, genres].compactMap { $0 }.joined(separator: " · ")

            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color(red: 209 / 255, green: 209 / 255, blue: 214 / 255))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Solid 4K + Dolby Vision + Outlined Technical Badges + Score

    @ViewBuilder
    private var technicalBadgesRow: some View {
        HStack(spacing: 12) {
            Text("4K")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color(red: 209 / 255, green: 209 / 255, blue: 214 / 255), in: RoundedRectangle(cornerRadius: 5))

            DolbyVisionBadgeView()

            ForEach(["5.1", "CC", "SDH", "AR"], id: \.self) { label in
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 229 / 255, green: 229 / 255, blue: 234 / 255))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(red: 174 / 255, green: 174 / 255, blue: 178 / 255), lineWidth: 1)
                    )
            }

            if let vote = viewModel.movieDetail?.voteAverage, vote > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 17))
                    Text(String(format: "%.1f", vote))
                }
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color(red: 209 / 255, green: 209 / 255, blue: 214 / 255))
                .padding(.leading, 4)
            }
        }
    }

    // MARK: - 3-Line Synopsis

    @ViewBuilder
    private var overviewSection: some View {
        if let overview = viewModel.movieDetail?.overview, !overview.isEmpty {
            Text(overview)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Color(red: 209 / 255, green: 209 / 255, blue: 214 / 255))
                .lineLimit(3)
                .lineSpacing(5)
                .frame(maxWidth: 740, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Action Buttons Row (72pt Scale + Isolated Leaf Focus)

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 16) {
            let hasProgress = viewModel.watchProgress.map { $0.progress > 0 && !$0.isCompleted } ?? false
            let playLabel = hasProgress
                ? (viewModel.watchProgress?.remainingTimeFormatted.isEmpty == false ? viewModel.watchProgress!.remainingTimeFormatted : "Resume")
                : "Play"

            DetailPlayPillButton(
                title: playLabel,
                progress: hasProgress ? viewModel.watchProgress?.progress : nil
            ) {
                playMovie()
            }

            if hasProgress {
                DetailSecondaryPillButton(title: "Rewatch", systemName: "arrow.counterclockwise") {
                    rewatchMovie()
                }
            }

            DetailCircleGlassButton(
                systemName: viewModel.isWatched ? "checkmark.circle.fill" : "checkmark.circle",
                isActive: viewModel.isWatched
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

            DetailCircleGlassButton(
                systemName: "paintpalette",
                isActive: customArtwork != nil
            ) {
                showChangeArtwork = true
            }

            DetailCircleGlassButton(systemName: "ellipsis") {
                showMoreOptions = true
            }
        }
    }

    // MARK: - Cast Section (32pt Bold Header + 150x150 Circular Portraits)

    @ViewBuilder
    private var castSection: some View {
        if !viewModel.cast.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                Text("Cast")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 32) {
                        ForEach(viewModel.cast.prefix(20)) { member in
                            CastCardView(member: member, imageSize: 150)
                                .equatable()
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 12)
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
        activeStreamFetchTask?.cancel()
        activeStreamFetchTask = Task {
            isLoadingStreams = true
            isLoadingMoreStreams = true
            streamError = nil
            availableStreams = []

            var didOpenOrLaunch = false
            do {
                if movieImdbId == nil {
                    let ext = try? await TMDBService.shared.fetchMovieExternalIds(id: tmdbId)
                    movieImdbId = ext?.imdbId
                }
                let streams = try await AIOStreamsService.shared.fetchStreamsProgressiveForMovie(
                    tmdbId: tmdbId,
                    preferredQuality: preferredQuality
                ) { partialStreams, stillLoading in
                    guard !Task.isCancelled else { return }
                    availableStreams = partialStreams
                    isLoadingMoreStreams = stillLoading
                    guard !didOpenOrLaunch,
                          let firstPlayable = partialStreams.first(where: { $0.url != nil && !($0.url?.isEmpty ?? true) }) ?? partialStreams.first else {
                        return
                    }
                    selectedStream = firstPlayable
                    isLoadingStreams = false
                    if !forcePicker && (playAtOnceEnabled || (!stillLoading && partialStreams.count == 1)),
                       let url = URL(string: firstPlayable.url ?? "") {
                        didOpenOrLaunch = true
                        activeStreamFetchTask?.cancel()
                        startPlayback(url: url, stream: firstPlayable, resumeFrom: effectiveResumeTime)
                    } else if !forcePicker && playAtOnceEnabled {
                        return
                    } else {
                        didOpenOrLaunch = true
                        showStreamPicker = true
                    }
                }
                guard !Task.isCancelled else { return }
                isLoadingStreams = false
                isLoadingMoreStreams = false
                availableStreams = streams
                if !didOpenOrLaunch {
                    let firstPlayable = streams.first(where: { $0.url != nil && !($0.url?.isEmpty ?? true) }) ?? streams.first
                    selectedStream = firstPlayable
                    if !forcePicker && (playAtOnceEnabled || streams.count == 1),
                       let chosen = firstPlayable,
                       let url = URL(string: chosen.url ?? "") {
                        startPlayback(url: url, stream: chosen, resumeFrom: effectiveResumeTime)
                    } else {
                        showStreamPicker = true
                    }
                }
            } catch is CancellationError {
                isLoadingStreams = false
                isLoadingMoreStreams = false
            } catch {
                isLoadingStreams = false
                isLoadingMoreStreams = false
                if !didOpenOrLaunch {
                    streamError = error.localizedDescription
                }
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

            let playerVM = PlayerViewModel()
            playerVM.loadSubtitleSettingsFromPreferences(context: modelContext)
            playerVM.configure(
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
            playerViewModel = playerVM
            showStreamPicker = false
            showPlayer = true
        }
    }
}
