import Foundation
import SwiftData
import Observation
import os

@Observable
final class HomeViewModel {

    // MARK: - Published State

    var spotlightItems: [TMDBMovie] = []
    var spotlightLogos: [Int: String] = [:]
    var spotlightRuntimes: [Int: Int] = [:]
    var spotlightCertifications: [Int: String] = [:]

    var continueWatching: [WatchHistory] = []
    var trendingMovies: [TMDBMovie] = []
    var trendingSeries: [TMDBSeries] = []

    var watchedMovieIds: Set<Int> = []
    var watchedSeriesIds: Set<Int> = []

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
        loadWatchedState(context: context)

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
                let topSeven = Array(movies.results.prefix(7))
                self.spotlightItems = topSeven

                self.prefetchHomeImages()
                self.syncTopShelfSnapshot()

                Self.logger.notice("Loaded \(movies.results.count) trending movies and \(series.results.count) trending series")
                print("[HomeViewModel] Loaded \(movies.results.count) trending movies and \(series.results.count) trending series")

                // Enrich top hero items with official TMDB logos, runtimes, and certifications in parallel
                await self.enrichSpotlightItems(topSeven)
            } catch {
                self.error = error.localizedDescription
                Self.logger.error("TMDB fetch failed: \(error.localizedDescription, privacy: .public)")
                print("[HomeViewModel] TMDB fetch failed: \(error)")
            }
        }

        activeLoadTask = task
        await task.value
    }

    // MARK: - Spotlight Enrichment

    @MainActor
    private func enrichSpotlightItems(_ items: [TMDBMovie]) async {
        let tmdbService = self.service
        await withTaskGroup(of: (Int, String?, Int?, String?).self) { group in
            for item in items {
                group.addTask {
                    async let logo = tmdbService.fetchBestLogoPath(mediaType: "movie", id: item.id)
                    async let detail = try? tmdbService.fetchMovieDetails(id: item.id)

                    let (resolvedLogo, resolvedDetail) = await (logo, detail)
                    let runtime = resolvedDetail?.runtime
                    let cert = Self.extractUSCertification(from: resolvedDetail)
                    return (item.id, resolvedLogo, runtime, cert)
                }
            }

            for await (id, logo, runtime, cert) in group {
                if let logo {
                    spotlightLogos[id] = logo
                }
                if let runtime, runtime > 0 {
                    spotlightRuntimes[id] = runtime
                }
                if let cert, !cert.isEmpty {
                    spotlightCertifications[id] = cert
                }
            }
        }
    }

    private nonisolated static func extractUSCertification(from detail: TMDBMovieDetail?) -> String? {
        guard let results = detail?.releaseDates?.results else { return nil }
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

    // MARK: - SwiftData Queries

    @MainActor
    func loadContinueWatching(context: ModelContext) {
        let descriptor = FetchDescriptor<WatchHistory>(
            predicate: #Predicate<WatchHistory> { item in
                !item.isCompleted && item.currentTime > 0
            },
            sortBy: [SortDescriptor(\.lastWatched, order: .reverse)]
        )

        do {
            continueWatching = try context.fetch(descriptor)
            prefetchContinueWatchingImages()
            syncTopShelfSnapshot()
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func prefetchContinueWatchingImages() {
        let urls: [URL] = continueWatching.prefix(12).compactMap { item in
            let path = item.episodeStillPath ?? item.backdropPath ?? item.posterPath
            return service.imageURL(path: path, size: "w780")
        }
        AuraImageCache.shared.prefetch(urls: urls, targetSize: CGSize(width: 340, height: 191))
    }

    @MainActor
    private func prefetchHomeImages() {
        let heroURLs = spotlightItems.compactMap {
            service.imageURL(path: $0.backdropPath ?? $0.posterPath, size: "w1280")
        }
        AuraImageCache.shared.prefetch(urls: heroURLs, targetSize: CGSize(width: 1440, height: 640))

        var posterURLs: [URL] = []
        posterURLs.reserveCapacity(40)
        for movie in trendingMovies.prefix(20) {
            if let url = service.imageURL(path: movie.posterPath, size: "w500") {
                posterURLs.append(url)
            }
        }
        for show in trendingSeries.prefix(20) {
            if let url = service.imageURL(path: show.posterPath, size: "w500") {
                posterURLs.append(url)
            }
        }
        AuraImageCache.shared.prefetch(urls: posterURLs, targetSize: CGSize(width: 215, height: 322))
    }

    @MainActor
    func syncTopShelfSnapshot() {
        let cwEntries: [TopShelfEntry] = continueWatching.prefix(10).map { item in
            let subtitle: String
            if item.mediaType == "series", let s = item.seasonNumber, let e = item.episodeNumber {
                if let epTitle = item.episodeTitle, !epTitle.isEmpty {
                    subtitle = "S\(s) E\(e) · \(epTitle)"
                } else {
                    subtitle = "S\(s) E\(e) · \(item.remainingTimeFormatted) left"
                }
            } else {
                subtitle = "\(item.remainingTimeFormatted) left"
            }

            return TopShelfEntry(
                tmdbId: item.tmdbId,
                mediaType: item.mediaType,
                title: item.title,
                subtitle: subtitle,
                imagePath: item.episodeStillPath ?? item.backdropPath ?? item.posterPath,
                isContinueWatching: true
            )
        }

        var featuredEntries: [TopShelfEntry] = []
        let maxPairs = max(trendingMovies.prefix(6).count, trendingSeries.prefix(6).count)
        for idx in 0..<maxPairs {
            if idx < trendingMovies.count {
                let movie = trendingMovies[idx]
                featuredEntries.append(TopShelfEntry(
                    tmdbId: movie.id,
                    mediaType: "movie",
                    title: movie.title,
                    subtitle: movie.releaseDate.map { String($0.prefix(4)) },
                    imagePath: movie.posterPath ?? movie.backdropPath,
                    isContinueWatching: false
                ))
            }
            if idx < trendingSeries.count {
                let show = trendingSeries[idx]
                featuredEntries.append(TopShelfEntry(
                    tmdbId: show.id,
                    mediaType: "series",
                    title: show.name,
                    subtitle: show.firstAirDate.map { String($0.prefix(4)) },
                    imagePath: show.posterPath ?? show.backdropPath,
                    isContinueWatching: false
                ))
            }
        }

        let snapshot = TopShelfSnapshot(
            tmdbApiKey: service.apiKey,
            updatedAt: Date(),
            continueWatching: cwEntries,
            featured: featuredEntries
        )
        TopShelfSharedStore.save(snapshot)
    }

    @MainActor
    func loadWatchedState(context: ModelContext) {
        let descriptor = FetchDescriptor<WatchHistory>(
            predicate: #Predicate<WatchHistory> { item in
                item.isCompleted
            }
        )

        do {
            let completed = try context.fetch(descriptor)
            watchedMovieIds = Set(completed.filter { $0.mediaType == "movie" }.map(\.tmdbId))
            watchedSeriesIds = Set(completed.filter { $0.mediaType == "series" }.map(\.tmdbId))
        } catch {
            watchedMovieIds = []
            watchedSeriesIds = []
        }
    }

    // MARK: - Refresh

    @MainActor
    func refresh(context: ModelContext) async {
        await loadAll(context: context, force: true)
    }
}
