import SwiftUI
import SwiftData

// MARK: - Home View

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @Query private var artworkOverrides: [CustomArtwork]
    @State private var viewModel = HomeViewModel()

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
                item.customBackdropPath.map { (item.tmdbId, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var customMoviePosters: [Int: String] {
        Dictionary(
            artworkOverrides.filter { $0.mediaType == "movie" }.compactMap { item in
                item.customPosterPath.map { (item.tmdbId, $0) }
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

    private var customSeriesPosters: [Int: String] {
        Dictionary(
            artworkOverrides.filter { $0.mediaType == "series" }.compactMap { item in
                item.customPosterPath.map { (item.tmdbId, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var customContinueBackdrops: [String: String] {
        Dictionary(
            artworkOverrides.compactMap { item in
                item.customBackdropPath.map { (item.key, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        ZStack {
            AuraDynamicBackgroundView(
                styleSetting: backgroundStyle,
                fallbackBackdropURL: TMDBService.shared.imageURL(
                    path: viewModel.spotlightItems.first?.backdropPath,
                    size: "w1280"
                )
            )

            if viewModel.isLoading && viewModel.trendingMovies.isEmpty {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .focusable()
                    .auraLeftEdgeSidebarTrigger()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 34) {
                        // Hero Spotlight / Ambient Banner
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

                        // Continue Watching Row (16:9 cards with flush bottom progress bar)
                        ContinueWatchingRow(
                            items: viewModel.continueWatching,
                            backdropOverrides: customContinueBackdrops,
                            autoPlayTrailersOnFocus: autoPlayTrailersOnFocus
                        )

                        // Series Shelf (2:3 clean portrait posters with count)
                        let firstSeriesId = viewModel.trendingSeries.first?.id
                        MediaRowView(title: "Series", count: viewModel.trendingSeries.count) {
                            ForEach(viewModel.trendingSeries) { series in
                                SeriesPosterCardView(
                                    series: series,
                                    overridePosterPath: customSeriesPosters[series.id],
                                    isWatched: viewModel.watchedSeriesIds.contains(series.id),
                                    showWatchedBadge: showWatchedIndicators,
                                    autoPlayTrailersOnFocus: autoPlayTrailersOnFocus,
                                    isFirstInRow: series.id == firstSeriesId
                                )
                            }
                        }

                        // Movies Shelf (2:3 clean portrait posters with count)
                        let firstMovieId = viewModel.trendingMovies.first?.id
                        MediaRowView(title: "Movies", count: viewModel.trendingMovies.count) {
                            ForEach(viewModel.trendingMovies) { movie in
                                PosterCardView(
                                    movie: movie,
                                    overridePosterPath: customMoviePosters[movie.id],
                                    isWatched: viewModel.watchedMovieIds.contains(movie.id),
                                    showWatchedBadge: showWatchedIndicators,
                                    autoPlayTrailersOnFocus: autoPlayTrailersOnFocus,
                                    isFirstInRow: movie.id == firstMovieId
                                )
                            }
                        }

                        Spacer().frame(height: 60)
                    }
                }
                .ignoresSafeArea(.container, edges: heroStyle == .ambient ? [.top, .horizontal] : [])
            }
        }
        .task {
            await viewModel.loadAll(context: modelContext)
        }
        .refreshable {
            await viewModel.refresh(context: modelContext)
        }
        .onDisappear {
            AppThemeCoordinator.shared.clearHomePreview()
        }
    }
}
