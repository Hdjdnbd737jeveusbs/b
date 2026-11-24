import SwiftUI
import SwiftData

// MARK: - Home View

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HomeViewModel()

    var body: some View {
        ZStack {
            Color.auraBackground.ignoresSafeArea()

            if viewModel.isLoading && viewModel.trendingMovies.isEmpty {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 36) {
                        // Hero Spotlight Carousel
                        SpotlightCarouselView(items: viewModel.spotlightItems)
                            .padding(.horizontal, 50)
                            .padding(.top, 20)

                        // Continue Watching Row (16:9 cards)
                        ContinueWatchingRow(items: viewModel.continueWatching)

                        // Trending Movies Shelf (2:3 posters)
                        MediaRowView(title: "Trending Movies") {
                            ForEach(viewModel.trendingMovies) { movie in
                                PosterCardView(movie: movie)
                            }
                        }

                        // Trending Series Shelf (16:9 cards)
                        MediaRowView(title: "Trending Series") {
                            ForEach(viewModel.trendingSeries) { series in
                                SeriesCardView(series: series)
                            }
                        }

                        Spacer().frame(height: 60)
                    }
                }
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
