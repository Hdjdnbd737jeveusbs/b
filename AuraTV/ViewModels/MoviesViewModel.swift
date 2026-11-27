import Foundation
import Observation
import os

enum MovieCategory: String, CaseIterable, Identifiable {
    case popular = "Popular"
    case topRated = "Top Rated"
    case nowPlaying = "Now Playing"
    case upcoming = "Upcoming"

    var id: String { rawValue }
}

@Observable
final class MoviesViewModel {

    // MARK: - Published State

    var popularMovies: [TMDBMovie] = []
    var topRatedMovies: [TMDBMovie] = []
    var nowPlayingMovies: [TMDBMovie] = []
    var upcomingMovies: [TMDBMovie] = []
    var selectedCategory: MovieCategory = .popular
    var isLoading: Bool = false
    var error: String?

    // MARK: - Pagination

    private var popularPage: Int = 1
    private var topRatedPage: Int = 1
    private var nowPlayingPage: Int = 1
    private var upcomingPage: Int = 1

    private var popularTotalPages: Int = 1
    private var topRatedTotalPages: Int = 1
    private var nowPlayingTotalPages: Int = 1
    private var upcomingTotalPages: Int = 1

    private var isLoadingMore: Bool = false

    // MARK: - Dependencies

    private let service = TMDBService.shared
    private var activeLoadTask: Task<Void, Never>?
    private static let logger = Logger(subsystem: "com.auratv.AuraTV", category: "Movies")

    // MARK: - Initial Load

    /// Loads the first page of all categories.
    @MainActor
    func loadMovies(force: Bool = false) async {
        if !force && !popularMovies.isEmpty {
            return
        }

        if let activeLoadTask {
            await activeLoadTask.value
            return
        }

        isLoading = popularMovies.isEmpty
        error = nil

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isLoading = false
                self.activeLoadTask = nil
            }

            Self.logger.notice("Fetching TMDB movies categories...")
            do {
                async let popular = self.service.fetchPopularMovies(page: 1)
                async let topRated = self.service.fetchTopRatedMovies(page: 1)
                async let nowPlaying = self.service.fetchNowPlayingMovies(page: 1)
                async let upcoming = self.service.fetchUpcomingMovies(page: 1)

                let (popularRes, topRatedRes, nowPlayingRes, upcomingRes) =
                    try await (popular, topRated, nowPlaying, upcoming)

                self.popularMovies = popularRes.results
                self.popularPage = popularRes.page
                self.popularTotalPages = popularRes.totalPages

                self.topRatedMovies = topRatedRes.results
                self.topRatedPage = topRatedRes.page
                self.topRatedTotalPages = topRatedRes.totalPages

                self.nowPlayingMovies = nowPlayingRes.results
                self.nowPlayingPage = nowPlayingRes.page
                self.nowPlayingTotalPages = nowPlayingRes.totalPages

                self.upcomingMovies = upcomingRes.results
                self.upcomingPage = upcomingRes.page
                self.upcomingTotalPages = upcomingRes.totalPages

                self.prefetchMovies(Array(popularRes.results.prefix(20)))

                Self.logger.notice("Loaded \(popularRes.results.count) popular, \(topRatedRes.results.count) topRated, \(nowPlayingRes.results.count) nowPlaying, \(upcomingRes.results.count) upcoming movies")
                print("[MoviesViewModel] Loaded \(popularRes.results.count) popular movies")
            } catch {
                self.error = error.localizedDescription
                Self.logger.error("TMDB movies fetch failed: \(error.localizedDescription, privacy: .public)")
                print("[MoviesViewModel] TMDB fetch failed: \(error)")
            }
        }

        activeLoadTask = task
        await task.value
    }

    // MARK: - Load More (Pagination)

    /// Loads the next page for the given category.
    @MainActor
    func loadCategory(category: MovieCategory) async {
        guard !isLoadingMore else { return }

        switch category {
        case .popular:
            guard popularPage < popularTotalPages else { return }
            isLoadingMore = true
            do {
                let response = try await service.fetchPopularMovies(page: popularPage + 1)
                popularMovies.append(contentsOf: response.results)
                popularPage = response.page
                popularTotalPages = response.totalPages
            } catch {
                self.error = error.localizedDescription
            }

        case .topRated:
            guard topRatedPage < topRatedTotalPages else { return }
            isLoadingMore = true
            do {
                let response = try await service.fetchTopRatedMovies(page: topRatedPage + 1)
                topRatedMovies.append(contentsOf: response.results)
                topRatedPage = response.page
                topRatedTotalPages = response.totalPages
            } catch {
                self.error = error.localizedDescription
            }

        case .nowPlaying:
            guard nowPlayingPage < nowPlayingTotalPages else { return }
            isLoadingMore = true
            do {
                let response = try await service.fetchNowPlayingMovies(page: nowPlayingPage + 1)
                nowPlayingMovies.append(contentsOf: response.results)
                nowPlayingPage = response.page
                nowPlayingTotalPages = response.totalPages
            } catch {
                self.error = error.localizedDescription
            }

        case .upcoming:
            guard upcomingPage < upcomingTotalPages else { return }
            isLoadingMore = true
            do {
                let response = try await service.fetchUpcomingMovies(page: upcomingPage + 1)
                upcomingMovies.append(contentsOf: response.results)
                upcomingPage = response.page
                upcomingTotalPages = response.totalPages
            } catch {
                self.error = error.localizedDescription
            }
        }

        isLoadingMore = false
    }

    @MainActor
    func prefetchMovies(_ items: [TMDBMovie]) {
        let posterURLs = items.compactMap { service.imageURL(path: $0.posterPath, size: "w500") }
        AuraImageCache.shared.prefetch(urls: posterURLs, targetSize: CGSize(width: 215, height: 322))
    }

    // MARK: - Helpers

    /// Returns the movies array for a given category.
    func movies(for category: MovieCategory) -> [TMDBMovie] {
        switch category {
        case .popular: return popularMovies
        case .topRated: return topRatedMovies
        case .nowPlaying: return nowPlayingMovies
        case .upcoming: return upcomingMovies
        }
    }

    /// Whether more pages are available for the given category.
    func hasMorePages(for category: MovieCategory) -> Bool {
        switch category {
        case .popular: return popularPage < popularTotalPages
        case .topRated: return topRatedPage < topRatedTotalPages
        case .nowPlaying: return nowPlayingPage < nowPlayingTotalPages
        case .upcoming: return upcomingPage < upcomingTotalPages
        }
    }
}
