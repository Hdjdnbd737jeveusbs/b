import SwiftUI
import SwiftData

// MARK: - Home View

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @State private var viewModel = HomeViewModel()

    private var heroStyle: HomeHeroStyle {
        HomeHeroStyle(settingValue: settingsList.first?.homeHeroStyle ?? "Ambient")
    }

    private var showWatchedIndicators: Bool {
        settingsList.first?.showWatchedIndicators ?? true
    }

    private var includeLogos: Bool {
        settingsList.first?.includeLogosInHome ?? true
    }

    var body: some View {
        ZStack {
            Color.auraBackground.ignoresSafeArea()

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
                            logos: viewModel.spotlightLogos,
                            runtimes: viewModel.spotlightRuntimes,
                            certifications: viewModel.spotlightCertifications,
                            showLogos: includeLogos
                        )

                        // Continue Watching Row (16:9 cards with flush bottom progress bar)
                        ContinueWatchingRow(items: viewModel.continueWatching)

                        // Series Shelf (2:3 clean portrait posters with count)
                        MediaRowView(title: "Series", count: viewModel.trendingSeries.count) {
                            ForEach(viewModel.trendingSeries) { series in
                                SeriesPosterCardView(
                                    series: series,
                                    isWatched: viewModel.watchedSeriesIds.contains(series.id),
                                    showWatchedBadge: showWatchedIndicators
                                )
                            }
                        }

                        // Movies Shelf (2:3 clean portrait posters with count)
                        MediaRowView(title: "Movies", count: viewModel.trendingMovies.count) {
                            ForEach(viewModel.trendingMovies) { movie in
                                PosterCardView(
                                    movie: movie,
                                    isWatched: viewModel.watchedMovieIds.contains(movie.id),
                                    showWatchedBadge: showWatchedIndicators
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
    }
}
