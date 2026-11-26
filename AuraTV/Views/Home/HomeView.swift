import SwiftUI
import SwiftData

// MARK: - Home View

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @Query private var artworkOverrides: [CustomArtwork]
    @State private var viewModel = HomeViewModel()

    @State private var addonShelves: [AddonShelf] = []
    private var enabledAddons: [URL] {
        AIOStreamsService.shared.addons.filter(\.enabled).map(\.endpoint)
    }

    private var heroStyle: HomeHeroStyle {
        HomeHeroStyle(settingValue: settingsList.first?.homeHeroStyle ?? "Ambient")
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
                            logos: viewModel.spotlightLogos.merging(customMovieLogos) { _, custom in custom },
                            runtimes: viewModel.spotlightRuntimes,
                            certifications: viewModel.spotlightCertifications,
                            customBackdrops: customMovieBackdrops,
                            showLogos: includeLogos
                        )

                        // Continue Watching Row (16:9 cards with flush bottom progress bar)
                        ContinueWatchingRow(
                            items: viewModel.continueWatching,
                            backdropOverrides: customContinueBackdrops
                        )

                        ForEach(addonShelves) { shelf in
                            MediaRowView(title: shelf.name, count: shelf.titles.count) {
                                ForEach(shelf.titles) { item in
                                    NavigationLink {
                                        AddonTitleDestination(title: item, type: shelf.type)
                                    } label: {
                                        VStack {
                                            AsyncImage(url: item.poster) { image in image.resizable().scaledToFit() }
                                                placeholder: { Color.gray.opacity(0.2) }
                                                .frame(width: 170, height: 245)
                                            Text(item.name).lineLimit(1).frame(width: 170)
                                        }
                                    }
                                }
                            }
                        }

                        // Series Shelf (2:3 clean portrait posters with count)
                        MediaRowView(title: "Series", count: viewModel.trendingSeries.count) {
                            ForEach(viewModel.trendingSeries) { series in
                                SeriesPosterCardView(
                                    series: series,
                                    overridePosterPath: customSeriesPosters[series.id],
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
                                    overridePosterPath: customMoviePosters[movie.id],
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
        .task(id: enabledAddons) {
            let shelves = await AIOStreamsService.shared.fetchShelves()
            if !Task.isCancelled { addonShelves = shelves }
        }
        .refreshable {
            await viewModel.refresh(context: modelContext)
        }
    }
}

private struct AddonTitleDestination: View {
    let title: AddonTitle
    let type: String
    @State private var tmdbId: Int?
    @State private var error: String?

    var body: some View {
        Group {
            if let tmdbId {
                if type == "movie" { MovieDetailView(tmdbId: tmdbId) }
                else { SeriesDetailView(tmdbId: tmdbId) }
            } else if let error { Text(error) }
            else { ProgressView() }
        }
        .task(id: title.id) {
            do { tmdbId = try await TMDBService.shared.resolveIMDb(title.id, type: type) }
            catch { self.error = error.localizedDescription }
        }
    }
}
