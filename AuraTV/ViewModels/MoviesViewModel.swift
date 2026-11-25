import Foundation
import Observation

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

    // MARK: - Initial Load

    /// Loads the first page of all categories.
    @MainActor
    func loadMovies() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            async let popular = service.fetchPopularMovies(page: 1)
            async let topRated = service.fetchTopRatedMovies(page: 1)
            async let nowPlaying = service.fetchNowPlayingMovies(page: 1)
            async let upcoming = service.fetchUpcomingMovies(page: 1)

            let (popularRes, topRatedRes, nowPlayingRes, upcomingRes) =
                try await (popular, topRated, nowPlaying, upcoming)

            popularMovies = popularRes.results
            popularPage = popularRes.page
            popularTotalPages = popularRes.totalPages

            topRatedMovies = topRatedRes.results
            topRatedPage = topRatedRes.page
            topRatedTotalPages = topRatedRes.totalPages

            nowPlayingMovies = nowPlayingRes.results
            nowPlayingPage = nowPlayingRes.page
            nowPlayingTotalPages = nowPlayingRes.totalPages

            upcomingMovies = upcomingRes.results
            upcomingPage = upcomingRes.page
            upcomingTotalPages = upcomingRes.totalPages
        } catch {
            self.error = error.localizedDescription
            print("[MoviesViewModel] TMDB fetch failed: \(error)")
        }

        isLoading = false
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
