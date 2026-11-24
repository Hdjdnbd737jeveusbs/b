import Foundation
import SwiftData
import Observation

@Observable
final class HomeViewModel {

    // MARK: - Published State

    var spotlightItems: [TMDBMovie] = []
    var continueWatching: [WatchHistory] = []
    var trendingMovies: [TMDBMovie] = []
    var trendingSeries: [TMDBSeries] = []
    var isLoading: Bool = false
    var error: String?

    // MARK: - Dependencies

    private let service = TMDBService.shared

    // MARK: - Load All

    @MainActor
    func loadAll(context: ModelContext) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            async let moviesResponse = service.fetchTrendingMovies(page: 1)
            async let seriesResponse = service.fetchTrendingSeries(page: 1)

            let (movies, series) = try await (moviesResponse, seriesResponse)

            trendingMovies = movies.results
            trendingSeries = series.results

            // Top 7 trending movies for the hero carousel
            spotlightItems = Array(movies.results.prefix(7))

            // Load continue watching from SwiftData
            loadContinueWatching(context: context)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Continue Watching

    @MainActor
    func loadContinueWatching(context: ModelContext) {
        let descriptor = FetchDescriptor<WatchHistory>(
            predicate: #Predicate<WatchHistory> { item in
                !item.isCompleted && item.currentTime > 0
            },
            sortBy: [SortDescriptor(\.lastWatched, order: .reverse)]
        )

        do {
            let results = try context.fetch(descriptor)
            continueWatching = results
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Refresh

    @MainActor
    func refresh(context: ModelContext) async {
        await loadAll(context: context)
    }
}
