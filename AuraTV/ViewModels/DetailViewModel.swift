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
    var logoPath: String?
    var cast: [TMDBCastMember] = []
    var certification: String?
    var mdblistRatings: MDBListRatingsSummary?
    var episodeWatchedVersion: Int = 0
    var revealedEpisodeTokens: Set<String> = []
    var showAllSpoilers: Bool = false
    var isLoading: Bool = false
    var isInWatchlist: Bool = false
    var isWatched: Bool = false
    var watchProgress: WatchHistory?
    var error: String?

    var watchProgressFraction: Double {
        watchProgress?.progress ?? 0
    }

    var remainingTimeFormatted: String {
        watchProgress?.remainingTimeFormatted ?? ""
    }

    // MARK: - Dependencies

    private let service = TMDBService.shared
    private var activeLoadTask: Task<Void, Never>?

    // MARK: - Movie Detail

    @MainActor
    func loadMovieDetail(id: Int, context: ModelContext? = nil) async {
        activeLoadTask?.cancel()

        isLoading = true
        error = nil
        movieDetail = nil
        seriesDetail = nil
        seasonDetail = nil
        logoPath = nil
        cast = []
        certification = nil
        mdblistRatings = nil

        if let context {
            checkWatchlistStatus(tmdbId: id, mediaType: "movie", context: context)
            loadWatchProgress(tmdbId: id, mediaType: "movie", context: context)
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }

            do {
                async let detailFetch = self.service.fetchMovieDetails(id: id)
                async let logoFetch = self.service.fetchBestLogoPath(mediaType: "movie", id: id)
                async let ratingsFetch = MDBListService.shared.fetchRatings(tmdbId: id, mediaType: "movie")

                let detail = try await detailFetch
                let resolvedLogo = await logoFetch
                let resolvedRatings = await ratingsFetch
                self.movieDetail = detail
                self.logoPath = resolvedLogo
                self.mdblistRatings = resolvedRatings
                self.cast = detail.credits?.cast ?? []
                self.certification = self.extractMovieCertification(from: detail)
                self.prefetchDetailAssets(
                    backdropPath: detail.backdropPath,
                    posterPath: detail.posterPath,
                    cast: self.cast
                )
            } catch {
                self.error = error.localizedDescription
            }
        }

        activeLoadTask = task
        await task.value
    }

    // MARK: - Series Detail

    @MainActor
    func loadSeriesDetail(id: Int, context: ModelContext? = nil) async {
        activeLoadTask?.cancel()

        isLoading = true
        error = nil
        movieDetail = nil
        seriesDetail = nil
        seasonDetail = nil
        logoPath = nil
        cast = []
        certification = nil
        mdblistRatings = nil

        if let context {
            checkWatchlistStatus(tmdbId: id, mediaType: "series", context: context)
            loadWatchProgress(tmdbId: id, mediaType: "series", context: context)
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }

            do {
                async let detailFetch = self.service.fetchSeriesDetails(id: id)
                async let logoFetch = self.service.fetchBestLogoPath(mediaType: "tv", id: id)
                async let ratingsFetch = MDBListService.shared.fetchRatings(tmdbId: id, mediaType: "series")

                let detail = try await detailFetch
                let resolvedLogo = await logoFetch
                let resolvedRatings = await ratingsFetch
                self.seriesDetail = detail
                self.logoPath = resolvedLogo
                self.mdblistRatings = resolvedRatings
                self.cast = detail.credits?.cast ?? []
                self.certification = self.extractSeriesCertification(from: detail)

                if let seasons = detail.seasons, !seasons.isEmpty {
                    let targetSeason = self.watchProgress?.seasonNumber
                        ?? (seasons.first(where: { $0.seasonNumber > 0 }) ?? seasons.first!).seasonNumber
                    self.selectedSeasonNumber = targetSeason
                    await self.loadSeasonDetail(seriesId: id, seasonNumber: targetSeason)
                }
                self.prefetchDetailAssets(
                    backdropPath: detail.backdropPath,
                    posterPath: detail.posterPath,
                    cast: self.cast,
                    episodes: self.seasonDetail?.episodes ?? []
                )
            } catch {
                self.error = error.localizedDescription
            }
        }

        activeLoadTask = task
        await task.value
    }

    // MARK: - Season Detail

    @MainActor
    func loadSeasonDetail(seriesId: Int, seasonNumber: Int) async {
        do {
            let detail = try await service.fetchSeasonDetails(seriesId: seriesId, seasonNumber: seasonNumber)
            seasonDetail = detail
            selectedSeasonNumber = seasonNumber
            prefetchDetailAssets(episodes: detail.episodes ?? [])
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func prefetchDetailAssets(
        backdropPath: String? = nil,
        posterPath: String? = nil,
        cast: [TMDBCastMember] = [],
        episodes: [TMDBEpisode] = []
    ) {
        var urls: [URL] = []
        if let backdrop = service.imageURL(path: backdropPath, size: "original") {
            urls.append(backdrop)
        }
        if let poster = service.imageURL(path: posterPath, size: "w500") {
            urls.append(poster)
        }
        for member in cast.prefix(15) {
            if let profile = service.imageURL(path: member.profilePath, size: "w185") {
                urls.append(profile)
            }
        }
        for ep in episodes.prefix(16) {
            if let still = service.imageURL(path: ep.stillPath, size: "w500") {
                urls.append(still)
            }
        }
        AuraImageCache.shared.prefetch(urls: urls)
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
            isWatched = items.first?.isCompleted ?? false
        } catch {
            watchProgress = nil
            isWatched = false
        }
    }

    @MainActor
    func toggleWatched(
        tmdbId: Int,
        mediaType: String,
        title: String,
        posterPath: String?,
        backdropPath: String?,
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
                history.isCompleted.toggle()
                history.lastWatched = Date()
                isWatched = history.isCompleted
                watchProgress = history
            } else {
                let history = WatchHistory(
                    tmdbId: tmdbId,
                    mediaType: mediaType,
                    title: title,
                    posterPath: posterPath,
                    backdropPath: backdropPath,
                    isCompleted: true
                )
                context.insert(history)
                isWatched = true
                watchProgress = history
            }
            try context.save()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Episode Spoiler & Watched Helpers

    @MainActor
    func isEpisodeWatched(tmdbId: Int, season: Int, episode: Int) -> Bool {
        _ = episodeWatchedVersion
        if isWatched { return true }
        if EpisodeWatchedStore.isWatched(tmdbId: tmdbId, season: season, episode: episode) {
            return true
        }
        if let progress = watchProgress,
           let ps = progress.seasonNumber,
           let pe = progress.episodeNumber {
            if ps > season { return true }
            if ps == season && (pe > episode || (pe == episode && progress.isCompleted)) {
                return true
            }
        }
        return false
    }

    @MainActor
    func toggleEpisodeWatched(tmdbId: Int, season: Int, episode: Int) {
        EpisodeWatchedStore.toggleWatched(tmdbId: tmdbId, season: season, episode: episode)
        episodeWatchedVersion += 1
    }

    @MainActor
    func isEpisodeSpoilerRevealed(season: Int, episode: Int) -> Bool {
        showAllSpoilers || revealedEpisodeTokens.contains("S\(season)E\(episode)")
    }

    @MainActor
    func toggleEpisodeSpoilerReveal(season: Int, episode: Int) {
        let key = "S\(season)E\(episode)"
        if revealedEpisodeTokens.contains(key) {
            revealedEpisodeTokens.remove(key)
        } else {
            revealedEpisodeTokens.insert(key)
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
            isWatched = true
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
            isWatched = history.isCompleted
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
