import Foundation
import Observation

enum SeriesCategory: String, CaseIterable, Identifiable {
    case popular = "Popular"
    case topRated = "Top Rated"
    case airingToday = "Airing Today"
    case onTheAir = "On The Air"

    var id: String { rawValue }
}

@Observable
final class SeriesViewModel {

    // MARK: - Published State

    var popularSeries: [TMDBSeries] = []
    var topRatedSeries: [TMDBSeries] = []
    var airingTodaySeries: [TMDBSeries] = []
    var onTheAirSeries: [TMDBSeries] = []
    var selectedCategory: SeriesCategory = .popular
    var isLoading: Bool = false
    var error: String?

    // MARK: - Pagination

    private var popularPage: Int = 1
    private var topRatedPage: Int = 1
    private var airingTodayPage: Int = 1
    private var onTheAirPage: Int = 1

    private var popularTotalPages: Int = 1
    private var topRatedTotalPages: Int = 1
    private var airingTodayTotalPages: Int = 1
    private var onTheAirTotalPages: Int = 1

    private var isLoadingMore: Bool = false

    // MARK: - Dependencies

    private let service = TMDBService.shared

    // MARK: - Initial Load

    /// Loads the first page of all categories.
    @MainActor
    func loadSeries() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            async let popular = service.fetchPopularSeries(page: 1)
            async let topRated = service.fetchTopRatedSeries(page: 1)
            async let airingToday = service.fetchAiringTodaySeries(page: 1)
            async let onTheAir = service.fetchOnTheAirSeries(page: 1)

            let (popularRes, topRatedRes, airingTodayRes, onTheAirRes) =
                try await (popular, topRated, airingToday, onTheAir)

            popularSeries = popularRes.results
            popularPage = popularRes.page
            popularTotalPages = popularRes.totalPages

            topRatedSeries = topRatedRes.results
            topRatedPage = topRatedRes.page
            topRatedTotalPages = topRatedRes.totalPages

            airingTodaySeries = airingTodayRes.results
            airingTodayPage = airingTodayRes.page
            airingTodayTotalPages = airingTodayRes.totalPages

            onTheAirSeries = onTheAirRes.results
            onTheAirPage = onTheAirRes.page
            onTheAirTotalPages = onTheAirRes.totalPages
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Load More (Pagination)

    /// Loads the next page for the given category.
    @MainActor
    func loadCategory(category: SeriesCategory) async {
        guard !isLoadingMore else { return }

        switch category {
        case .popular:
            guard popularPage < popularTotalPages else { return }
            isLoadingMore = true
            do {
                let response = try await service.fetchPopularSeries(page: popularPage + 1)
                popularSeries.append(contentsOf: response.results)
                popularPage = response.page
                popularTotalPages = response.totalPages
            } catch {
                self.error = error.localizedDescription
            }

        case .topRated:
            guard topRatedPage < topRatedTotalPages else { return }
            isLoadingMore = true
            do {
                let response = try await service.fetchTopRatedSeries(page: topRatedPage + 1)
                topRatedSeries.append(contentsOf: response.results)
                topRatedPage = response.page
                topRatedTotalPages = response.totalPages
            } catch {
                self.error = error.localizedDescription
            }

        case .airingToday:
            guard airingTodayPage < airingTodayTotalPages else { return }
            isLoadingMore = true
            do {
                let response = try await service.fetchAiringTodaySeries(page: airingTodayPage + 1)
                airingTodaySeries.append(contentsOf: response.results)
                airingTodayPage = response.page
                airingTodayTotalPages = response.totalPages
            } catch {
                self.error = error.localizedDescription
            }

        case .onTheAir:
            guard onTheAirPage < onTheAirTotalPages else { return }
            isLoadingMore = true
            do {
                let response = try await service.fetchOnTheAirSeries(page: onTheAirPage + 1)
                onTheAirSeries.append(contentsOf: response.results)
                onTheAirPage = response.page
                onTheAirTotalPages = response.totalPages
            } catch {
                self.error = error.localizedDescription
            }
        }

        isLoadingMore = false
    }

    // MARK: - Helpers

    /// Returns the series array for a given category.
    func series(for category: SeriesCategory) -> [TMDBSeries] {
        switch category {
        case .popular: return popularSeries
        case .topRated: return topRatedSeries
        case .airingToday: return airingTodaySeries
        case .onTheAir: return onTheAirSeries
        }
    }

    /// Whether more pages are available for the given category.
    func hasMorePages(for category: SeriesCategory) -> Bool {
        switch category {
        case .popular: return popularPage < popularTotalPages
        case .topRated: return topRatedPage < topRatedTotalPages
        case .airingToday: return airingTodayPage < airingTodayTotalPages
        case .onTheAir: return onTheAirPage < onTheAirTotalPages
        }
    }
}
