import SwiftUI
import SwiftData

// MARK: - Series Detail View (Full-Bleed Backdrop + TMDB Logo + Episode Controls)

struct SeriesDetailView: View {
    let tmdbId: Int

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = DetailViewModel()
    @FocusState private var focusedButton: SeriesButton?

    // Streaming state
    @State private var showStreamPicker = false
    @State private var showPlayer = false
    @State private var showMoreOptions = false
    @State private var availableStreams: [StremioStream] = []
    @State private var isLoadingStreams = false
    @State private var streamError: String?
    @State private var playerViewModel = PlayerViewModel()
    @State private var pendingEpisodeSeason: Int?
    @State private var pendingEpisodeNumber: Int?
    @State private var pendingEpisodeTitle: String?
    @State private var pendingEpisodeStillPath: String?
    @State private var seriesImdbId: String?

    enum SeriesButton: Hashable {
        case play
        case watched
        case watchlist
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
                    VStack(alignment: .leading, spacing: 34) {
                        // Left hero metadata column
                        VStack(alignment: .leading, spacing: 18) {
                            Spacer().frame(height: geometry.size.height * 0.13)

                            titleSection

                            metadataLine

                            technicalBadgesRow

                            overviewSection

                            currentEpisodeSubtitle

                            actionButtons
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: geometry.size.width * 0.54, alignment: .leading)
                        .padding(.leading, 80)

                        // Full-width Episodes section with Season selector pill
                        episodesSection

                        // Full-width circular Cast row
                        castSection

                        Spacer().frame(height: 60)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .task {
            await viewModel.loadSeriesDetail(id: tmdbId, context: modelContext)
        }
        .sheet(isPresented: $showStreamPicker) {
            StreamPickerSheet(
                title: streamPickerTitle,
                streams: availableStreams,
                onSelect: { stream in
                    if let urlString = stream.url, let url = URL(string: urlString) {
                        startPlayback(
                            url: url,
                            season: pendingEpisodeSeason ?? 1,
                            episode: pendingEpisodeNumber ?? 1,
                            episodeTitle: pendingEpisodeTitle,
                            stillPath: pendingEpisodeStillPath,
                            resumeFrom: (viewModel.watchProgress?.seasonNumber == pendingEpisodeSeason && viewModel.watchProgress?.episodeNumber == pendingEpisodeNumber) ? (viewModel.watchProgress?.currentTime ?? 0) : 0
                        )
                    }
                },
                onDismiss: { showStreamPicker = false }
            )
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView(viewModel: playerViewModel)
        }
        .confirmationDialog("Options", isPresented: $showMoreOptions, titleVisibility: .visible) {
            Button("Choose Stream Source...") {
                playSeries(forcePicker: true)
            }
            Button(viewModel.isWatched ? "Mark as Unwatched" : "Mark as Watched") {
                viewModel.toggleWatched(
                    tmdbId: tmdbId,
                    mediaType: "series",
                    title: viewModel.seriesDetail?.name ?? "",
                    posterPath: viewModel.seriesDetail?.posterPath,
                    backdropPath: viewModel.seriesDetail?.backdropPath,
                    context: modelContext
                )
            }
            Button("Restart from S1 • E1") {
                rewatchSeries()
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

    // MARK: - Backdrop Layer with Vignettes

    @ViewBuilder
    private func backdropLayer(geometry: GeometryProxy) -> some View {
        let height = geometry.size.height * 0.78
        ZStack(alignment: .topTrailing) {
            if let path = viewModel.seriesDetail?.backdropPath ?? viewModel.seriesDetail?.posterPath,
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
        if let detail = viewModel.seriesDetail {
            TitleLogoView(
                title: detail.name,
                mediaType: "tv",
                tmdbId: detail.id,
                preloadedLogoPath: viewModel.logoPath,
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

    // MARK: - Metadata Line

    @ViewBuilder
    private var metadataLine: some View {
        if let detail = viewModel.seriesDetail {
            HStack(spacing: 10) {
                if let date = detail.firstAirDate, date.count >= 4 {
                    Text(String(date.prefix(4)))
                }

                if let cert = viewModel.certification, !cert.isEmpty {
                    Text("•")
                        .foregroundStyle(.white.opacity(0.5))
                    BadgeView(text: cert, style: .outlined, fontSize: 12)
                }

                if let numSeasons = detail.numberOfSeasons, numSeasons > 0 {
                    Text("•")
                        .foregroundStyle(.white.opacity(0.5))
                    Text("\(numSeasons) Season\(numSeasons == 1 ? "" : "s")")
                }

                if let genres = detail.genres, !genres.isEmpty {
                    Text("•")
                        .foregroundStyle(.white.opacity(0.5))
                    Text(genres.map(\.name).prefix(3).joined(separator: ", "))
                        .lineLimit(1)
                }
            }
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(.white.opacity(0.86))
        }
    }

    // MARK: - Technical Badges + Star Rating

    @ViewBuilder
    private var technicalBadgesRow: some View {
        HStack(spacing: 8) {
            BadgeView(text: "4K", style: .outlined, fontSize: 12)
            BadgeView(text: "Dolby Vision", style: .outlined, fontSize: 12)
            BadgeView(text: "5.1", style: .outlined, fontSize: 12)
            BadgeView(text: "CC", style: .outlined, fontSize: 12)
            BadgeView(text: "SDH", style: .outlined, fontSize: 12)
            BadgeView(text: "AR", style: .outlined, fontSize: 12)

            if let vote = viewModel.seriesDetail?.voteAverage, vote > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 14))
                    Text(String(format: "%.1f", vote))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.leading, 6)
            }
        }
    }

    // MARK: - 3-Line Synopsis

    @ViewBuilder
    private var overviewSection: some View {
        if let overview = viewModel.seriesDetail?.overview, !overview.isEmpty {
            Text(overview)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(3)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Current Episode Subtitle ("S2 • E1 - Episode Title")

    @ViewBuilder
    private var currentEpisodeSubtitle: some View {
        if let ep = activeEpisode {
            Text("S\(ep.seasonNumber) • E\(ep.episodeNumber) - \(ep.name)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
        }
    }

    private var activeEpisode: TMDBEpisode? {
        if let progress = viewModel.watchProgress,
           let s = progress.seasonNumber,
           let e = progress.episodeNumber,
           let matched = viewModel.seasonDetail?.episodes?.first(where: { $0.seasonNumber == s && $0.episodeNumber == e }) {
            return matched
        }
        return viewModel.seasonDetail?.episodes?.first
    }

    // MARK: - Action Buttons Row

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 14) {
            Button(action: { playSeries() }) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18))

                    if let progress = viewModel.watchProgress,
                       progress.progress > 0 && !progress.isCompleted,
                       !progress.remainingTimeFormatted.isEmpty {
                        Text(progress.remainingTimeFormatted)
                            .font(.system(size: 19, weight: .bold))
                    } else {
                        Text("Play")
                            .font(.system(size: 19, weight: .bold))
                    }
                }
                .padding(.horizontal, 34)
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
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .focused($focusedButton, equals: .play)
            .scaleEffect(focusedButton == .play ? 1.07 : 1.0)
            .animation(.easeOut(duration: 0.18), value: focusedButton)

            circleGlassButton(
                systemName: "checkmark",
                isActive: viewModel.isWatched,
                target: .watched
            ) {
                viewModel.toggleWatched(
                    tmdbId: tmdbId,
                    mediaType: "series",
                    title: viewModel.seriesDetail?.name ?? "",
                    posterPath: viewModel.seriesDetail?.posterPath,
                    backdropPath: viewModel.seriesDetail?.backdropPath,
                    context: modelContext
                )
            }

            circleGlassButton(
                systemName: viewModel.isInWatchlist ? "bookmark.fill" : "bookmark",
                isActive: viewModel.isInWatchlist,
                target: .watchlist
            ) {
                viewModel.toggleWatchlist(
                    tmdbId: tmdbId,
                    mediaType: "series",
                    title: viewModel.seriesDetail?.name ?? "",
                    posterPath: viewModel.seriesDetail?.posterPath,
                    backdropPath: viewModel.seriesDetail?.backdropPath,
                    context: modelContext
                )
            }

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
        target: SeriesButton,
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
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($focusedButton, equals: target)
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .animation(.easeOut(duration: 0.18), value: focusedButton)
    }

    // MARK: - Episodes Section with Season Picker Pill

    @ViewBuilder
    private var episodesSection: some View {
        let seasons = viewModel.seriesDetail?.seasons?.filter { $0.seasonNumber > 0 }
            ?? viewModel.seriesDetail?.seasons
            ?? []

        if !seasons.isEmpty || !(viewModel.seasonDetail?.episodes?.isEmpty ?? true) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Episodes")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)

                    if !seasons.isEmpty {
                        Menu {
                            ForEach(seasons) { season in
                                Button {
                                    Task {
                                        await viewModel.loadSeasonDetail(
                                            seriesId: tmdbId,
                                            seasonNumber: season.seasonNumber
                                        )
                                    }
                                } label: {
                                    HStack {
                                        Text(season.name)
                                        if season.seasonNumber == viewModel.selectedSeasonNumber {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text("Season \(viewModel.selectedSeasonNumber)")
                                    .font(.system(size: 16, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.12), in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 80)

                if let episodes = viewModel.seasonDetail?.episodes, !episodes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 22) {
                            ForEach(episodes) { episode in
                                EpisodeCardView(episode: episode) {
                                    playEpisode(episode: episode)
                                }
                            }
                        }
                        .padding(.horizontal, 80)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
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

    // MARK: - Playback Helpers

    private var streamPickerTitle: String {
        let name = viewModel.seriesDetail?.name ?? "Series"
        if let s = pendingEpisodeSeason, let e = pendingEpisodeNumber {
            return "\(name) · S\(s):E\(e)"
        }
        return name
    }

    private func playSeries(forcePicker: Bool = false) {
        let s = viewModel.watchProgress?.seasonNumber ?? viewModel.selectedSeasonNumber
        let e = viewModel.watchProgress?.episodeNumber ?? 1
        let ep = viewModel.seasonDetail?.episodes?.first(where: { $0.seasonNumber == s && $0.episodeNumber == e })
            ?? viewModel.seasonDetail?.episodes?.first

        if let ep {
            fetchAndPlayEpisode(
                season: ep.seasonNumber,
                episode: ep.episodeNumber,
                title: ep.name,
                stillPath: ep.stillPath,
                forcePicker: forcePicker
            )
        } else {
            fetchAndPlayEpisode(season: s, episode: e, title: nil, stillPath: nil, forcePicker: forcePicker)
        }
    }

    private func rewatchSeries() {
        if let progress = viewModel.watchProgress {
            progress.currentTime = 0
            progress.isCompleted = false
            progress.seasonNumber = 1
            progress.episodeNumber = 1
            try? modelContext.save()
        }
        if let firstEp = viewModel.seasonDetail?.episodes?.first(where: { $0.episodeNumber == 1 }) {
            playEpisode(episode: firstEp)
        } else {
            fetchAndPlayEpisode(season: 1, episode: 1, title: nil, stillPath: nil)
        }
    }

    func playEpisode(episode: TMDBEpisode) {
        fetchAndPlayEpisode(
            season: episode.seasonNumber,
            episode: episode.episodeNumber,
            title: episode.name,
            stillPath: episode.stillPath
        )
    }

    private func fetchAndPlayEpisode(season: Int, episode: Int, title: String?, stillPath: String?, forcePicker: Bool = false) {
        pendingEpisodeSeason = season
        pendingEpisodeNumber = episode
        pendingEpisodeTitle = title
        pendingEpisodeStillPath = stillPath

        Task {
            isLoadingStreams = true
            streamError = nil
            do {
                if seriesImdbId == nil {
                    let ext = try? await TMDBService.shared.fetchSeriesExternalIds(id: tmdbId)
                    seriesImdbId = ext?.imdbId
                }
                let streams = try await AIOStreamsService.shared.fetchStreamsForEpisode(
                    tmdbId: tmdbId,
                    season: season,
                    episode: episode
                )
                availableStreams = streams
                isLoadingStreams = false

                if !forcePicker && streams.count == 1, let url = URL(string: streams[0].url ?? "") {
                    startPlayback(
                        url: url,
                        season: season,
                        episode: episode,
                        episodeTitle: title,
                        stillPath: stillPath,
                        resumeFrom: (viewModel.watchProgress?.seasonNumber == season && viewModel.watchProgress?.episodeNumber == episode) ? (viewModel.watchProgress?.currentTime ?? 0) : 0
                    )
                } else {
                    showStreamPicker = true
                }
            } catch {
                isLoadingStreams = false
                streamError = error.localizedDescription
            }
        }
    }

    private func startPlayback(
        url: URL,
        season: Int,
        episode: Int,
        episodeTitle: String?,
        stillPath: String?,
        resumeFrom: Double = 0
    ) {
        let detail = viewModel.seriesDetail
        playerViewModel = PlayerViewModel()
        playerViewModel.configure(
            url: url,
            title: detail?.name ?? "Series",
            backdropPath: detail?.backdropPath,
            posterPath: detail?.posterPath,
            tmdbId: tmdbId,
            mediaType: "series",
            seasonNumber: season,
            episodeNumber: episode,
            episodeTitle: episodeTitle,
            episodeStillPath: stillPath,
            resumeFrom: resumeFrom,
            imdbId: seriesImdbId ?? ""
        )
        showStreamPicker = false
        showPlayer = true
    }
}
