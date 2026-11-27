import SwiftUI
import SwiftData

// MARK: - Series Detail View (Full-Bleed Backdrop + TMDB Logo + Episode Controls)

struct SeriesDetailView: View {
    let tmdbId: Int

    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @Query private var artworkOverrides: [CustomArtwork]
    @State private var viewModel = DetailViewModel()
    @FocusState private var focusedButton: SeriesButton?

    // Streaming state
    @State private var showStreamPicker = false
    @State private var showPlayer = false
    @State private var showMoreOptions = false
    @State private var showChangeArtwork = false
    @State private var availableStreams: [StremioStream] = []
    @State private var selectedStream: StremioStream?
    @State private var isLoadingStreams = false
    @State private var streamError: String?
    @State private var playerViewModel = PlayerViewModel()
    @State private var pendingEpisodeSeason: Int?
    @State private var pendingEpisodeNumber: Int?
    @State private var pendingEpisodeTitle: String?
    @State private var pendingEpisodeStillPath: String?
    @State private var seriesImdbId: String?

    private var customArtwork: CustomArtwork? {
        let key = CustomArtwork.makeKey(tmdbId: tmdbId, mediaType: "series")
        return artworkOverrides.first { $0.key == key }
    }

    private var effectivePosterPath: String? {
        customArtwork?.customPosterPath ?? viewModel.seriesDetail?.posterPath
    }

    private var effectiveBackdropPath: String? {
        customArtwork?.customBackdropPath ?? viewModel.seriesDetail?.backdropPath ?? effectivePosterPath
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

    private var blurUnwatchedThumbnails: Bool {
        settingsList.first?.blurUnwatchedEpisodeThumbnails ?? false
    }

    private var hideUnwatchedDescriptions: Bool {
        settingsList.first?.hideUnwatchedEpisodeDescriptions ?? false
    }

    private func effectiveResumeTime(forSeason season: Int, episode: Int) -> Double {
        guard let progress = viewModel.watchProgress,
              progress.seasonNumber == season,
              progress.episodeNumber == episode else {
            return 0
        }
        let settings = settingsList.first
        return ExternalPlayerService.adjustedResumeTime(
            rawTime: progress.currentTime,
            behavior: settings?.resumePlaybackBehavior ?? "Ask",
            rewindSeconds: settings?.rewindOnResumeSeconds ?? 5
        )
    }

    enum SeriesButton: Hashable {
        case play
        case rewatch
        case watched
        case artwork
        case more
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                AuraDynamicBackgroundView(
                    styleSetting: settingsList.first?.backgroundStyle ?? "Soft Glow",
                    fallbackBackdropURL: effectiveBackdropPath.flatMap { TMDBService.shared.imageURL(path: $0, size: "original") }
                )

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

                            if let ratings = viewModel.mdblistRatings, !ratings.isEmpty {
                                MDBListRatingsRow(ratings: ratings)
                            }

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
            AppThemeCoordinator.shared.updateFocusedArtwork(
                posterPath: effectivePosterPath,
                backdropPath: effectiveBackdropPath
            )
        }
        .sheet(isPresented: $showStreamPicker) {
            StreamPickerSheet(
                title: streamPickerTitle,
                streams: availableStreams,
                selectedStream: selectedStream,
                preferredQuality: preferredQuality,
                onSelect: { stream in
                    selectedStream = stream
                    if let urlString = stream.url, let url = URL(string: urlString) {
                        let s = pendingEpisodeSeason ?? 1
                        let e = pendingEpisodeNumber ?? 1
                        startPlayback(
                            url: url,
                            stream: stream,
                            season: s,
                            episode: e,
                            episodeTitle: pendingEpisodeTitle,
                            stillPath: pendingEpisodeStillPath,
                            resumeFrom: effectiveResumeTime(forSeason: s, episode: e)
                        )
                    }
                },
                onDismiss: { showStreamPicker = false }
            )
        }
        .fullScreenCover(isPresented: $showChangeArtwork) {
            ChangeArtworkView(
                tmdbId: tmdbId,
                mediaType: "series",
                title: viewModel.seriesDetail?.name ?? "Series",
                defaultPosterPath: viewModel.seriesDetail?.posterPath,
                defaultBackdropPath: viewModel.seriesDetail?.backdropPath,
                defaultLogoPath: viewModel.logoPath
            )
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView(viewModel: playerViewModel)
        }
        .confirmationDialog("Options", isPresented: $showMoreOptions, titleVisibility: .visible) {
            Button("Choose Stream Source...") {
                playSeries(forcePicker: true)
            }
            Button(viewModel.isInWatchlist ? "Remove from Watchlist" : "Add to Watchlist") {
                viewModel.toggleWatchlist(
                    tmdbId: tmdbId,
                    mediaType: "series",
                    title: viewModel.seriesDetail?.name ?? "",
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
                    mediaType: "series",
                    title: viewModel.seriesDetail?.name ?? "",
                    posterPath: effectivePosterPath,
                    backdropPath: effectiveBackdropPath,
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
                            .font(.system(size: 25, weight: .medium))
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
            if let path = effectiveBackdropPath,
               let url = TMDBService.shared.imageURL(path: path, size: "original") {
                AuraCachedImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width * 0.78, height: height)
                        .clipped()
                } placeholder: {
                    backdropPlaceholder(width: geometry.size.width * 0.78, height: height)
                }
            } else {
                backdropPlaceholder(width: geometry.size.width * 0.78, height: height)
            }
        }
        .frame(width: geometry.size.width, height: height, alignment: .topTrailing)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.06), location: 0.24),
                    .init(color: .black.opacity(0.34), location: 0.46),
                    .init(color: .black, location: 0.85)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.45),
                    .init(color: .black.opacity(0.25), location: 0.80),
                    .init(color: .clear, location: 1.0)
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
        if let detail = viewModel.seriesDetail {
            TitleLogoView(
                title: detail.name,
                mediaType: "tv",
                tmdbId: detail.id,
                preloadedLogoPath: effectiveLogoPath,
                maxWidth: 640,
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
                    Text(cert)
                }

                if let numSeasons = detail.numberOfSeasons, numSeasons > 0 {
                    Text("•")
                        .foregroundStyle(.white.opacity(0.5))
                    Text("\(numSeasons) Season\(numSeasons == 1 ? "" : "s")")
                }

                if let genres = detail.genres, !genres.isEmpty {
                    Text("•")
                        .foregroundStyle(.white.opacity(0.5))
                    Text(genres.map(\.name).prefix(2).joined(separator: ", "))
                        .lineLimit(1)
                }
            }
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(.white.opacity(0.76))
        }
    }

    // MARK: - Technical Badges + Star Rating

    @ViewBuilder
    private var technicalBadgesRow: some View {
        HStack(spacing: 8) {
            BadgeView(text: "4K", style: .filled, fontSize: 12)
            DolbyVisionBadgeView()
            BadgeView(text: "5.1", style: .outlined, fontSize: 12)
            BadgeView(text: "CC", style: .outlined, fontSize: 12)
            BadgeView(text: "SDH", style: .outlined, fontSize: 12)
            BadgeView(text: "AR", style: .outlined, fontSize: 12)

            if let vote = viewModel.seriesDetail?.voteAverage, vote > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.white.opacity(0.65))
                        .font(.system(size: 16))
                    Text(String(format: "%.1f", vote))
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.leading, 4)
            }
        }
    }

    // MARK: - 3-Line Synopsis

    @ViewBuilder
    private var overviewSection: some View {
        if let overview = viewModel.seriesDetail?.overview, !overview.isEmpty {
            Text(overview)
                .font(.system(size: 22, weight: .regular))
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
                .font(.system(size: 21, weight: .semibold))
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
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 21))

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
                            .font(.system(size: 24, weight: .bold))
                    } else {
                        Text("Play")
                            .font(.system(size: 24, weight: .bold))
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

            if let progress = viewModel.watchProgress, progress.progress > 0 && !progress.isCompleted {
                Button(action: { rewatchSeries() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 20, weight: .semibold))
                        Text("Rewatch")
                            .font(.system(size: 22, weight: .semibold))
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

            circleGlassButton(
                systemName: "checkmark",
                isActive: viewModel.isWatched,
                target: .watched
            ) {
                viewModel.toggleWatched(
                    tmdbId: tmdbId,
                    mediaType: "series",
                    title: viewModel.seriesDetail?.name ?? "",
                    posterPath: effectivePosterPath,
                    backdropPath: effectiveBackdropPath,
                    context: modelContext
                )
            }

            circleGlassButton(
                systemName: "paintpalette",
                isActive: customArtwork != nil,
                target: .artwork
            ) {
                showChangeArtwork = true
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
                .font(.system(size: 22, weight: .bold))
                .frame(width: 64, height: 64)
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
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)

                    if !seasons.isEmpty || blurUnwatchedThumbnails || hideUnwatchedDescriptions {
                        HStack(spacing: 12) {
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
                                            .font(.system(size: 20, weight: .semibold))
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 15, weight: .bold))
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

                            if blurUnwatchedThumbnails || hideUnwatchedDescriptions {
                                Button {
                                    viewModel.showAllSpoilers.toggle()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: viewModel.showAllSpoilers ? "eye.fill" : "eye.slash.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                        Text(viewModel.showAllSpoilers ? "Hide Unwatched Spoilers" : "Reveal Spoilers")
                                            .font(.system(size: 19, weight: .semibold))
                                    }
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(.horizontal, 16)
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
                    }
                }
                .padding(.horizontal, 80)

                if let episodes = viewModel.seasonDetail?.episodes, !episodes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 22) {
                            ForEach(episodes) { episode in
                                EpisodeCardView(
                                    episode: episode,
                                    isWatched: viewModel.isEpisodeWatched(
                                        tmdbId: tmdbId,
                                        season: episode.seasonNumber,
                                        episode: episode.episodeNumber
                                    ),
                                    blurThumbnail: blurUnwatchedThumbnails,
                                    hideDescription: hideUnwatchedDescriptions,
                                    isSpoilerRevealed: viewModel.isEpisodeSpoilerRevealed(
                                        season: episode.seasonNumber,
                                        episode: episode.episodeNumber
                                    ),
                                    onToggleWatched: {
                                        viewModel.toggleEpisodeWatched(
                                            tmdbId: tmdbId,
                                            season: episode.seasonNumber,
                                            episode: episode.episodeNumber
                                        )
                                    },
                                    onToggleSpoilerReveal: {
                                        viewModel.toggleEpisodeSpoilerReveal(
                                            season: episode.seasonNumber,
                                            episode: episode.episodeNumber
                                        )
                                    }
                                ) {
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
                    .font(.system(size: 30, weight: .bold))
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

    private func fetchAndPlayEpisode(
        season: Int,
        episode: Int,
        title: String?,
        stillPath: String?,
        forcePicker: Bool = false,
        autoPlayBest: Bool = false
    ) {
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
                    episode: episode,
                    preferredQuality: preferredQuality
                )
                availableStreams = streams
                let firstPlayable = streams.first(where: { $0.url != nil && !($0.url?.isEmpty ?? true) }) ?? streams.first
                selectedStream = firstPlayable
                isLoadingStreams = false

                if (!forcePicker && (playAtOnceEnabled || streams.count == 1)) || autoPlayBest,
                   let chosen = firstPlayable,
                   let urlString = chosen.url,
                   let url = URL(string: urlString) {
                    startPlayback(
                        url: url,
                        stream: chosen,
                        season: season,
                        episode: episode,
                        episodeTitle: title,
                        stillPath: stillPath,
                        resumeFrom: autoPlayBest ? 0 : effectiveResumeTime(forSeason: season, episode: episode)
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
        stream: StremioStream? = nil,
        season: Int,
        episode: Int,
        episodeTitle: String?,
        stillPath: String?,
        resumeFrom: Double = 0
    ) {
        let detail = viewModel.seriesDetail
        let nextEp = viewModel.seasonDetail?.episodes?.first(where: {
            $0.seasonNumber == season && $0.episodeNumber == episode + 1
        })

        let seriesTitle = detail?.name ?? "Series"
        let displayTitle = episodeTitle.map { "\(seriesTitle) — S\(season) • E\(episode): \($0)" } ?? seriesTitle
        let externalName = settingsList.first?.externalPlayer ?? "Built-in AetherEngine"

        ExternalPlayerService.openExternalPlayerIfConfigured(
            playerName: externalName,
            streamURL: url,
            title: displayTitle
        ) { openedExternally in
            if openedExternally {
                showStreamPicker = false
                return
            }

            playerViewModel = PlayerViewModel()
            playerViewModel.configure(
                url: url,
                title: seriesTitle,
                overview: detail?.overview ?? "",
                backdropPath: effectiveBackdropPath,
                posterPath: effectivePosterPath,
                tmdbId: tmdbId,
                mediaType: "series",
                seasonNumber: season,
                episodeNumber: episode,
                episodeTitle: episodeTitle,
                episodeStillPath: stillPath,
                resumeFrom: resumeFrom,
                imdbId: seriesImdbId ?? "",
                availableStreams: availableStreams,
                selectedStream: stream ?? selectedStream,
                nextEpisode: nextEp,
                onPlayNextEpisode: { ep in
                    showPlayer = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        fetchAndPlayEpisode(
                            season: ep.seasonNumber,
                            episode: ep.episodeNumber,
                            title: ep.name,
                            stillPath: ep.stillPath,
                            autoPlayBest: true
                        )
                    }
                }
            )
            showStreamPicker = false
            showPlayer = true
        }
    }
}
