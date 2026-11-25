import Foundation
import SwiftData
import Observation
import os

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
    private var activeLoadTask: Task<Void, Never>?
    private static let logger = Logger(subsystem: "com.auratv.AuraTV", category: "Home")

    // MARK: - Load All

    @MainActor
    func loadAll(context: ModelContext, force: Bool = false) async {
        loadContinueWatching(context: context)

        if !force && !trendingMovies.isEmpty && !trendingSeries.isEmpty {
            return
        }

        if let activeLoadTask {
            await activeLoadTask.value
            return
        }

        isLoading = trendingMovies.isEmpty
        error = nil

        // Run inside an unstructured Task so SwiftUI .task cancellation
        // (e.g. during TabView / NavigationStack layout updates) does not cancel
        // the in-flight TMDB requests with NSURLErrorCancelled (-999).
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isLoading = false
                self.activeLoadTask = nil
            }

            Self.logger.notice("Fetching TMDB trending movies and series...")
            do {
                async let moviesResponse = self.service.fetchTrendingMovies(page: 1)
                async let seriesResponse = self.service.fetchTrendingSeries(page: 1)

                let (movies, series) = try await (moviesResponse, seriesResponse)

                self.trendingMovies = movies.results
                self.trendingSeries = series.results

                // Top 7 trending movies for the hero carousel
                self.spotlightItems = Array(movies.results.prefix(7))

                Self.logger.notice("Loaded \(movies.results.count) trending movies and \(series.results.count) trending series")
                print("[HomeViewModel] Loaded \(movies.results.count) trending movies and \(series.results.count) trending series")
            } catch {
                self.error = error.localizedDescription
                Self.logger.error("TMDB fetch failed: \(error.localizedDescription, privacy: .public)")
                print("[HomeViewModel] TMDB fetch failed: \(error)")
            }
        }

        activeLoadTask = task
        await task.value
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
        await loadAll(context: context, force: true)
    }
}
