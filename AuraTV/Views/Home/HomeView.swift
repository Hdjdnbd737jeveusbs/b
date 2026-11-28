import SwiftUI
import SwiftData

// MARK: - Home View

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @Query private var artworkOverrides: [CustomArtwork]
    let viewModel: HomeViewModel

    init(viewModel: HomeViewModel = HomeViewModel()) {
        self.viewModel = viewModel
    }

    @State private var artworkDate = Date()
    @State private var navMemory = AuraNavigationMemory.shared

    private var heroStyle: HomeHeroStyle {
        HomeHeroStyle(settingValue: settingsList.first?.homeHeroStyle ?? "Ambient")
    }

    private var backgroundStyle: String {
        settingsList.first?.backgroundStyle ?? "Soft Glow"
    }

    private var autoPlayTrailersOnFocus: Bool {
        settingsList.first?.autoPlayMutedTrailers ?? true
    }

    private var showWatchedIndicators: Bool {
        settingsList.first?.showWatchedIndicators ?? true
    }

    private var includeLogos: Bool {
        settingsList.first?.includeLogosInHome ?? true
    }

    private var customMovieBackdrops: [Int: String] {
        Dictionary(
            artworkOverrides.filter { $0.mediaType == "movie" }.compactMap { item in
                item.backdrop(at: artworkDate).map { (item.tmdbId, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var customSeriesBackdrops: [Int: String] {
        Dictionary(
            artworkOverrides.filter { $0.mediaType == "series" }.compactMap { item in
                item.backdrop(at: artworkDate).map { (item.tmdbId, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var customMovieLogos: [Int: String] {
        Dictionary(
            artworkOverrides.filter { $0.mediaType == "movie" }.compactMap { item in
                item.customLogoPath.map { (item.tmdbId, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var customSeriesLogos: [Int: String] {
        Dictionary(
            artworkOverrides.filter { $0.mediaType == "series" }.compactMap { item in
                item.customLogoPath.map { (item.tmdbId, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var customContinueBackdrops: [String: String] {
        Dictionary(
            artworkOverrides.compactMap { item in
                item.backdrop(at: artworkDate).map { (item.key, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isLoading && viewModel.trendingMovies.isEmpty {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .focusable()
                    .auraLeftEdgeSidebarTrigger()
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 36) {
                            // Hero Spotlight / Ambient Banner (zero top spacing offset so backdrop stays full-bleed)
                            SpotlightCarouselView(
                                items: viewModel.spotlightItems,
                                style: heroStyle,
                                logos: viewModel.spotlightLogos.merging(customMovieLogos) { _, custom in custom },
                                runtimes: viewModel.spotlightRuntimes,
                                certifications: viewModel.spotlightCertifications,
                                customBackdrops: customMovieBackdrops,
                                showLogos: includeLogos,
                                autoPlayTrailersOnFocus: autoPlayTrailersOnFocus
                            )
                            .id("home_top_anchor")
                            .background(
                                GeometryReader { geo in
                                    let y = geo.frame(in: .named("homeScroll")).minY
                                    Color.clear
                                        .onChange(of: y) { _, newY in
                                            AuraNavigationMemory.shared.setHomeScrolledPastHero(newY < -140)
                                        }
                                }
                            )
                            .focusSection()

                            // Continue Watching Row (16:9 400x225 cards)
                            ContinueWatchingRow(
                                items: viewModel.continueWatching,
                                backdropOverrides: customContinueBackdrops,
                                autoPlayTrailersOnFocus: autoPlayTrailersOnFocus
                            )

                            // TV Shows Shelf (16:9 400x225 horizontal landscape cards)
                            let firstSeriesId = viewModel.trendingSeries.first?.id
                            MediaRowView(title: "TV Shows") {
                                ForEach(viewModel.trendingSeries) { series in
                                    HomeLandscapeSeriesCard(
                                        series: series,
                                        overrideBackdropPath: customSeriesBackdrops[series.id],
                                        overrideLogoPath: customSeriesLogos[series.id] ?? viewModel.rowLogos["series_\(series.id)"],
                                        isWatched: viewModel.watchedSeriesIds.contains(series.id),
                                        showWatchedBadge: showWatchedIndicators,
                                        includeLogo: includeLogos,
                                        autoPlayTrailersOnFocus: autoPlayTrailersOnFocus,
                                        isFirstInRow: series.id == firstSeriesId
                                    )
                                    .equatable()
                                    .id("home_series_\(series.id)")
                                }
                            }

                            // Movies Shelf (16:9 400x225 horizontal landscape cards)
                            let firstMovieId = viewModel.trendingMovies.first?.id
                            MediaRowView(title: "Movies") {
                                ForEach(viewModel.trendingMovies) { movie in
                                    HomeLandscapeMovieCard(
                                        movie: movie,
                                        overrideBackdropPath: customMovieBackdrops[movie.id],
                                        overrideLogoPath: customMovieLogos[movie.id] ?? viewModel.rowLogos["movie_\(movie.id)"] ?? viewModel.spotlightLogos[movie.id],
                                        isWatched: viewModel.watchedMovieIds.contains(movie.id),
                                        showWatchedBadge: showWatchedIndicators,
                                        includeLogo: includeLogos,
                                        autoPlayTrailersOnFocus: autoPlayTrailersOnFocus,
                                        isFirstInRow: movie.id == firstMovieId
                                    )
                                    .equatable()
                                    .id("home_movie_\(movie.id)")
                                }
                            }

                            Spacer().frame(height: 60)
                        }
                    }
                    .coordinateSpace(name: "homeScroll")
                    .ignoresSafeArea(.container, edges: [.top, .horizontal])
                    .onChange(of: navMemory.homeScrollToTopTick) { _, _ in
                        withAnimation(.easeOut(duration: 0.35)) {
                            scrollProxy.scrollTo("home_top_anchor", anchor: .top)
                        }
                    }
                    .onChange(of: navMemory.restoreTick(for: "Home")) { _, _ in
                        if let scrollTarget = AuraNavigationMemory.shared.lastScrollId(for: "Home") {
                            scrollProxy.scrollTo(scrollTarget, anchor: .center)
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.loadAll(context: modelContext)
        }
        .task(id: artworkOverrides.contains(where: { $0.multipleArtworkEnabled })) {
            guard artworkOverrides.contains(where: { $0.multipleArtworkEnabled }) else { return }
            while !Task.isCancelled {
                artworkDate = Date()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .refreshable {
            await viewModel.refresh(context: modelContext)
        }
        .onDisappear {
            AppThemeCoordinator.shared.clearHomePreview()
            viewModel.stopPrefetchingHomeImages()
        }
    }
}

// MARK: - Home 16:9 Landscape Shelf Cards (400x225pt, CornerRadius 14pt)

private struct HomeLandscapeMovieCard: View, Equatable {
    let movie: TMDBMovie
    var overrideBackdropPath: String? = nil
    var overrideLogoPath: String? = nil
    var isWatched: Bool = false
    var showWatchedBadge: Bool = true
    var includeLogo: Bool = true
    var autoPlayTrailersOnFocus: Bool = false
    var isFirstInRow: Bool = false

    @FocusState private var isFocused: Bool
    @State private var navMemory = AuraNavigationMemory.shared

    private var focusId: String { "home_movie_\(movie.id)" }

    static func == (lhs: HomeLandscapeMovieCard, rhs: HomeLandscapeMovieCard) -> Bool {
        lhs.movie.id == rhs.movie.id &&
        lhs.overrideBackdropPath == rhs.overrideBackdropPath &&
        lhs.overrideLogoPath == rhs.overrideLogoPath &&
        lhs.isWatched == rhs.isWatched &&
        lhs.showWatchedBadge == rhs.showWatchedBadge &&
        lhs.includeLogo == rhs.includeLogo &&
        lhs.autoPlayTrailersOnFocus == rhs.autoPlayTrailersOnFocus &&
        lhs.isFirstInRow == rhs.isFirstInRow
    }

    private var subtitleLine: String {
        let year = movie.releaseDate.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil }
        let vote = movie.voteAverage.flatMap { $0 > 0 ? "★ \(String(format: "%.1f", $0))" : nil }
        let genre = TMDBGenres.movieGenreNames(for: movie.genreIds).first
        let joined = [year, vote, genre].compactMap { $0 }.joined(separator: " · ")
        return joined.isEmpty ? "Movie" : joined
    }

    var body: some View {
        NavigationLink(destination: MovieDetailView(tmdbId: movie.id)) {
            HomeLandscapeCardContent(
                title: movie.title,
                subtitle: subtitleLine,
                backdropPath: overrideBackdropPath ?? movie.backdropPath ?? movie.posterPath,
                logoPath: includeLogo ? overrideLogoPath : nil,
                isWatched: isWatched && showWatchedBadge,
                isFocused: isFocused,
                placeholderIcon: "film"
            )
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
        .auraLeftEdgeSidebarTrigger(isFirstInRow)
        .onChange(of: isFocused) { _, focused in
            if focused {
                AuraNavigationMemory.shared.recordFocus(tab: "Home", itemId: focusId)
                AuraNavigationMemory.shared.setHomeScrolledPastHero(true)
                AppThemeCoordinator.shared.onHomeCardFocused(
                    mediaType: "movie",
                    tmdbId: movie.id,
                    title: movie.title,
                    overview: movie.overview,
                    posterPath: movie.posterPath,
                    backdropPath: overrideBackdropPath ?? movie.backdropPath,
                    releaseYear: movie.releaseDate.map { String($0.prefix(4)) },
                    voteAverage: movie.voteAverage,
                    autoPlayTrailers: autoPlayTrailersOnFocus
                )
            } else if autoPlayTrailersOnFocus {
                AppThemeCoordinator.shared.onHomeCardBlurred(mediaType: "movie", tmdbId: movie.id)
            }
        }
        .onChange(of: navMemory.restoreTick(for: "Home")) { _, _ in
            if AuraNavigationMemory.shared.lastFocusedId(for: "Home") == focusId {
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
        }
        .modifier(MediaPosterContextMenuModifier(
            tmdbId: movie.id,
            mediaType: "movie",
            title: movie.title,
            posterPath: movie.posterPath,
            backdropPath: overrideBackdropPath ?? movie.backdropPath,
            initialWatched: isWatched
        ))
    }
}

private struct HomeLandscapeSeriesCard: View, Equatable {
    let series: TMDBSeries
    var overrideBackdropPath: String? = nil
    var overrideLogoPath: String? = nil
    var isWatched: Bool = false
    var showWatchedBadge: Bool = true
    var includeLogo: Bool = true
    var autoPlayTrailersOnFocus: Bool = false
    var isFirstInRow: Bool = false

    @FocusState private var isFocused: Bool
    @State private var navMemory = AuraNavigationMemory.shared

    private var focusId: String { "home_series_\(series.id)" }

    static func == (lhs: HomeLandscapeSeriesCard, rhs: HomeLandscapeSeriesCard) -> Bool {
        lhs.series.id == rhs.series.id &&
        lhs.overrideBackdropPath == rhs.overrideBackdropPath &&
        lhs.overrideLogoPath == rhs.overrideLogoPath &&
        lhs.isWatched == rhs.isWatched &&
        lhs.showWatchedBadge == rhs.showWatchedBadge &&
        lhs.includeLogo == rhs.includeLogo &&
        lhs.autoPlayTrailersOnFocus == rhs.autoPlayTrailersOnFocus &&
        lhs.isFirstInRow == rhs.isFirstInRow
    }

    private var subtitleLine: String {
        let year = series.firstAirDate.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil }
        let vote = series.voteAverage.flatMap { $0 > 0 ? "★ \(String(format: "%.1f", $0))" : nil }
        let genre = TMDBGenres.tvGenreNames(for: series.genreIds).first
        let joined = [year, vote, genre].compactMap { $0 }.joined(separator: " · ")
        return joined.isEmpty ? "TV Series" : joined
    }

    var body: some View {
        NavigationLink(destination: SeriesDetailView(tmdbId: series.id)) {
            HomeLandscapeCardContent(
                title: series.name,
                subtitle: subtitleLine,
                backdropPath: overrideBackdropPath ?? series.backdropPath ?? series.posterPath,
                logoPath: includeLogo ? overrideLogoPath : nil,
                isWatched: isWatched && showWatchedBadge,
                isFocused: isFocused,
                placeholderIcon: "tv"
            )
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
        .auraLeftEdgeSidebarTrigger(isFirstInRow)
        .onChange(of: isFocused) { _, focused in
            if focused {
                AuraNavigationMemory.shared.recordFocus(tab: "Home", itemId: focusId)
                AuraNavigationMemory.shared.setHomeScrolledPastHero(true)
                AppThemeCoordinator.shared.onHomeCardFocused(
                    mediaType: "series",
                    tmdbId: series.id,
                    title: series.name,
                    overview: series.overview,
                    posterPath: series.posterPath,
                    backdropPath: overrideBackdropPath ?? series.backdropPath,
                    releaseYear: series.firstAirDate.map { String($0.prefix(4)) },
                    voteAverage: series.voteAverage,
                    autoPlayTrailers: autoPlayTrailersOnFocus
                )
            } else if autoPlayTrailersOnFocus {
                AppThemeCoordinator.shared.onHomeCardBlurred(mediaType: "series", tmdbId: series.id)
            }
        }
        .onChange(of: navMemory.restoreTick(for: "Home")) { _, _ in
            if AuraNavigationMemory.shared.lastFocusedId(for: "Home") == focusId {
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
        }
        .modifier(MediaPosterContextMenuModifier(
            tmdbId: series.id,
            mediaType: "series",
            title: series.name,
            posterPath: series.posterPath,
            backdropPath: overrideBackdropPath ?? series.backdropPath,
            initialWatched: isWatched
        ))
    }
}

private struct HomeLandscapeCardContent: View {
    let title: String
    let subtitle: String
    let backdropPath: String?
    let logoPath: String?
    let isWatched: Bool
    let isFocused: Bool
    let placeholderIcon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                if let backdropPath,
                   let url = TMDBService.shared.imageURL(path: backdropPath, size: "w780") {
                    AuraCachedImage(url: url, targetSize: CGSize(width: 400, height: 225)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 400, height: 225)
                            .clipped()
                    } placeholder: {
                        cardPlaceholder
                    }
                } else {
                    cardPlaceholder
                }

                // Subtle bottom scrim + PNG logo overlay when available
                if let logoPath,
                   let logoURL = TMDBService.shared.imageURL(path: logoPath, size: "w500") {
                    LinearGradient(
                        colors: [Color.black.opacity(0.65), .clear],
                        startPoint: .bottom,
                        endPoint: .center
                    )

                    AuraCachedImage(url: logoURL, targetSize: CGSize(width: 220, height: 58), cropToFill: false) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 220, maxHeight: 58, alignment: .bottomLeading)
                    } placeholder: {
                        EmptyView()
                    }
                    .padding(16)
                }

                if isWatched {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.black.opacity(0.65), in: Circle())
                                .padding(10)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: 400, height: 225)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.14), lineWidth: isFocused ? 3.5 : 1)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255))
                    .lineLimit(1)
            }
            .frame(width: 400, alignment: .leading)
        }
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isFocused)
    }

    private var cardPlaceholder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.auraCardSurface)
            .frame(width: 400, height: 225)
            .overlay {
                Image(systemName: placeholderIcon)
                    .font(.system(size: 38))
                    .foregroundStyle(.white.opacity(0.25))
            }
    }
}
