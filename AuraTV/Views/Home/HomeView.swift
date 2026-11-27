import SwiftUI
import SwiftData

// MARK: - Home View

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @Query private var artworkOverrides: [CustomArtwork]
    @State private var viewModel = HomeViewModel()
    @State private var themeCoordinator = AppThemeCoordinator.shared

    @State private var artworkDate = Date()

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

    private var customMoviePosters: [Int: String] {
        Dictionary(
            artworkOverrides.filter { $0.mediaType == "movie" }.compactMap { item in
                item.poster(at: artworkDate).map { (item.tmdbId, $0) }
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
                item.poster(at: artworkDate).map { (item.tmdbId, $0) }
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
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 34) {
                        // Hero Spotlight / Ambient Banner
                        SpotlightCarouselView(
                            items: viewModel.spotlightItems,
                            style: heroStyle,
                            logos: viewModel.spotlightLogos.merging(customMovieLogos) { _, custom in custom },
                            runtimes: viewModel.spotlightRuntimes,
                            certifications: viewModel.spotlightCertifications,
                            customBackdrops: customMovieBackdrops,
                            showLogos: includeLogos,
                            trailerPreview: autoPlayTrailersOnFocus ? themeCoordinator.heroTrailerPreview : nil
                        )

                        // Continue Watching Row (16:9 cards with flush bottom progress bar)
                        ContinueWatchingRow(
                            items: viewModel.continueWatching,
                            backdropOverrides: customContinueBackdrops,
                            autoPlayTrailersOnFocus: autoPlayTrailersOnFocus
                        )

                        // Series Shelf (2:3 clean portrait posters with count)
                        MediaRowView(title: "Series", count: viewModel.trendingSeries.count) {
                            ForEach(viewModel.trendingSeries) { series in
                                SeriesPosterCardView(
                                    series: series,
                                    overridePosterPath: customSeriesPosters[series.id],
                                    isWatched: viewModel.watchedSeriesIds.contains(series.id),
                                    showWatchedBadge: showWatchedIndicators,
                                    autoPlayTrailersOnFocus: autoPlayTrailersOnFocus,
                                    posterWidth: 372
                                )
                            }
                        }

                        // Movies Shelf (2:3 clean portrait posters with count)
                        MediaRowView(title: "Movies", count: viewModel.trendingMovies.count) {
                            ForEach(viewModel.trendingMovies) { movie in
                                PosterCardView(
                                    movie: movie,
                                    overridePosterPath: customMoviePosters[movie.id],
                                    isWatched: viewModel.watchedMovieIds.contains(movie.id),
                                    showWatchedBadge: showWatchedIndicators,
                                    autoPlayTrailersOnFocus: autoPlayTrailersOnFocus,
                                    posterWidth: 372
                                )
                            }
                        }

                        Spacer().frame(height: 60)
                    }
                }
                .ignoresSafeArea(.container, edges: [.top, .horizontal])
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
            themeCoordinator.clearHomePreview()
        }
    }
}
