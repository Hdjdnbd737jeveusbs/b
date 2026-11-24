import Foundation
import SwiftData
import Observation

@Observable
final class DetailViewModel {

    // MARK: - Published State

    var movieDetail: TMDBMovieDetail?
    var seriesDetail: TMDBSeriesDetail?
    var seasonDetail: TMDBSeasonDetail?
    var selectedSeasonNumber: Int = 1
    var cast: [TMDBCastMember] = []
    var certification: String?
    var isLoading: Bool = false
    var isInWatchlist: Bool = false
    var watchProgress: WatchHistory?
    var error: String?

    // Computed progress helpers
    var watchProgressFraction: Double {
        watchProgress?.progress ?? 0
    }

    var remainingTimeFormatted: String {
        watchProgress?.remainingTimeFormatted ?? ""
    }

    // MARK: - Dependencies

    private let service = TMDBService.shared

    // MARK: - Movie Detail

    @MainActor
    func loadMovieDetail(id: Int, context: ModelContext? = nil) async {
        isLoading = true
        error = nil
        movieDetail = nil
        seriesDetail = nil
        seasonDetail = nil
        cast = []
        certification = nil

        do {
            let detail = try await service.fetchMovieDetails(id: id)
            movieDetail = detail
            cast = detail.credits?.cast ?? []
            certification = extractMovieCertification(from: detail)

            if let context {
                checkWatchlistStatus(tmdbId: id, mediaType: "movie", context: context)
                loadWatchProgress(tmdbId: id, mediaType: "movie", context: context)
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Series Detail

    @MainActor
    func loadSeriesDetail(id: Int, context: ModelContext? = nil) async {
        isLoading = true
        error = nil
        movieDetail = nil
        seriesDetail = nil
        seasonDetail = nil
        cast = []
        certification = nil

        do {
            let detail = try await service.fetchSeriesDetails(id: id)
            seriesDetail = detail
            cast = detail.credits?.cast ?? []
            certification = extractSeriesCertification(from: detail)

            if let context {
                checkWatchlistStatus(tmdbId: id, mediaType: "series", context: context)
                loadWatchProgress(tmdbId: id, mediaType: "series", context: context)
            }

            // Auto-load first season (prefer seasonNumber > 0)
            if let seasons = detail.seasons, !seasons.isEmpty {
                let firstSeason = seasons.first(where: { $0.seasonNumber > 0 }) ?? seasons.first!
                selectedSeasonNumber = firstSeason.seasonNumber
                await loadSeasonDetail(seriesId: id, seasonNumber: firstSeason.seasonNumber)
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Season Detail

    @MainActor
    func loadSeasonDetail(seriesId: Int, seasonNumber: Int) async {
        do {
            let detail = try await service.fetchSeasonDetails(seriesId: seriesId, seasonNumber: seasonNumber)
            seasonDetail = detail
            selectedSeasonNumber = seasonNumber
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Watchlist Management

    @MainActor
    func checkWatchlistStatus(tmdbId: Int, mediaType: String, context: ModelContext) {
        let descriptor = FetchDescriptor<WatchlistItem>(
            predicate: #Predicate<WatchlistItem> { item in
                item.tmdbId == tmdbId && item.mediaType == mediaType
            }
        )
        do {
            let items = try context.fetch(descriptor)
            isInWatchlist = !items.isEmpty
        } catch {
            isInWatchlist = false
        }
    }

    @MainActor
    func toggleWatchlist(
        tmdbId: Int,
        mediaType: String,
        title: String,
        posterPath: String?,
        backdropPath: String?,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<WatchlistItem>(
            predicate: #Predicate<WatchlistItem> { item in
                item.tmdbId == tmdbId && item.mediaType == mediaType
            }
        )

        do {
            let items = try context.fetch(descriptor)
            if let existing = items.first {
                context.delete(existing)
                isInWatchlist = false
            } else {
                let item = WatchlistItem(
                    tmdbId: tmdbId,
                    mediaType: mediaType,
                    title: title,
                    posterPath: posterPath,
                    backdropPath: backdropPath,
                    addedDate: Date()
                )
                context.insert(item)
                isInWatchlist = true
            }
            try context.save()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Watch Progress Management

    @MainActor
    func loadWatchProgress(tmdbId: Int, mediaType: String, context: ModelContext) {
        let descriptor = FetchDescriptor<WatchHistory>(
            predicate: #Predicate<WatchHistory> { item in
                item.tmdbId == tmdbId && item.mediaType == mediaType
            }
        )
        do {
            let items = try context.fetch(descriptor)
            watchProgress = items.first
        } catch {
            watchProgress = nil
        }
    }

    @MainActor
    func markAsWatched(
        tmdbId: Int,
        mediaType: String,
        title: String,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<WatchHistory>(
            predicate: #Predicate<WatchHistory> { item in
                item.tmdbId == tmdbId && item.mediaType == mediaType
            }
        )

        do {
            let existing = try context.fetch(descriptor)
            if let history = existing.first {
                history.isCompleted = true
                history.lastWatched = Date()
            } else {
                let history = WatchHistory(
                    tmdbId: tmdbId,
                    mediaType: mediaType,
                    title: title,
                    isCompleted: true
                )
                context.insert(history)
            }
            try context.save()
            watchProgress?.isCompleted = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    func updateWatchProgress(
        tmdbId: Int,
        mediaType: String,
        title: String,
        posterPath: String?,
        backdropPath: String?,
        currentTime: Double,
        totalDuration: Double,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil,
        episodeStillPath: String? = nil,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<WatchHistory>(
            predicate: #Predicate<WatchHistory> { item in
                item.tmdbId == tmdbId && item.mediaType == mediaType
            }
        )

        do {
            let existing = try context.fetch(descriptor)
            let history: WatchHistory

            if let found = existing.first {
                history = found
            } else {
                history = WatchHistory(
                    tmdbId: tmdbId,
                    mediaType: mediaType,
                    title: title,
                    posterPath: posterPath,
                    backdropPath: backdropPath
                )
                context.insert(history)
            }

            history.currentTime = currentTime
            history.totalDuration = totalDuration
            history.lastWatched = Date()
            history.seasonNumber = seasonNumber
            history.episodeNumber = episodeNumber
            history.episodeTitle = episodeTitle
            history.episodeStillPath = episodeStillPath

            if totalDuration > 0 {
                history.isCompleted = (currentTime / totalDuration) >= 0.95
            }

            try context.save()
            watchProgress = history
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Certification Extraction

    private func extractMovieCertification(from detail: TMDBMovieDetail) -> String? {
        guard let results = detail.releaseDates?.results else { return nil }

        if let usRelease = results.first(where: { $0.iso31661 == "US" }) {
            let sortedDates = usRelease.releaseDates?.sorted { ($0.type ?? 0) < ($1.type ?? 0) } ?? []

            if let theatrical = sortedDates.first(where: { $0.type == 3 && !($0.certification?.isEmpty ?? true) }) {
                return theatrical.certification
            }

            if let anyCert = sortedDates.first(where: { !($0.certification?.isEmpty ?? true) }) {
                return anyCert.certification
            }
        }

        return nil
    }

    private func extractSeriesCertification(from detail: TMDBSeriesDetail) -> String? {
        guard let results = detail.contentRatings?.results else { return nil }

        if let usRating = results.first(where: { $0.iso31661 == "US" }) {
            return usRating.rating
        }

        return nil
    }
}
