import Foundation
import Observation
import os

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
    private var activeLoadTask: Task<Void, Never>?
    private static let logger = Logger(subsystem: "com.auratv.AuraTV", category: "Series")

    // MARK: - Initial Load

    /// Loads the first page of all categories.
    @MainActor
    func loadSeries(force: Bool = false) async {
        if !force && !popularSeries.isEmpty {
            return
        }

        if let activeLoadTask {
            await activeLoadTask.value
            return
        }

        isLoading = popularSeries.isEmpty
        error = nil

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isLoading = false
                self.activeLoadTask = nil
            }

            Self.logger.notice("Fetching TMDB series categories...")
            do {
                async let popular = self.service.fetchPopularSeries(page: 1)
                async let topRated = self.service.fetchTopRatedSeries(page: 1)
                async let airingToday = self.service.fetchAiringTodaySeries(page: 1)
                async let onTheAir = self.service.fetchOnTheAirSeries(page: 1)

                let (popularRes, topRatedRes, airingTodayRes, onTheAirRes) =
                    try await (popular, topRated, airingToday, onTheAir)

                self.popularSeries = popularRes.results
                self.popularPage = popularRes.page
                self.popularTotalPages = popularRes.totalPages

                self.topRatedSeries = topRatedRes.results
                self.topRatedPage = topRatedRes.page
                self.topRatedTotalPages = topRatedRes.totalPages

                self.airingTodaySeries = airingTodayRes.results
                self.airingTodayPage = airingTodayRes.page
                self.airingTodayTotalPages = airingTodayRes.totalPages

                self.onTheAirSeries = onTheAirRes.results
                self.onTheAirPage = onTheAirRes.page
                self.onTheAirTotalPages = onTheAirRes.totalPages

                Self.logger.notice("Loaded \(popularRes.results.count) popular, \(topRatedRes.results.count) topRated, \(airingTodayRes.results.count) airingToday, \(onTheAirRes.results.count) onTheAir series")
                print("[SeriesViewModel] Loaded \(popularRes.results.count) popular series")
            } catch {
                self.error = error.localizedDescription
                Self.logger.error("TMDB series fetch failed: \(error.localizedDescription, privacy: .public)")
                print("[SeriesViewModel] TMDB fetch failed: \(error)")
            }
        }

        activeLoadTask = task
        await task.value
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
