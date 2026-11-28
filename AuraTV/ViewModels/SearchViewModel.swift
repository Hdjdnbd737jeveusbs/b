import Foundation
import Observation

@Observable
final class SearchViewModel {

    // MARK: - Published State

    var query: String = "" {
        didSet {
            handleQueryChange()
        }
    }
    var searchResults: [TMDBSearchResult] = []
    var recentSearches: [String] = RecentSearchStore.load()
    var isSearching: Bool = false
    var error: String?

    // MARK: - Debounce

    private var searchTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(300)

    // MARK: - Dependencies

    private let service = TMDBService.shared

    // MARK: - Search

    /// Performs a debounced 300ms off-MainActor multi-search against TMDB.
    @MainActor
    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        error = nil

        do {
            let svc = self.service
            let filtered = try await Task.detached(priority: .userInitiated) {
                let response = try await svc.searchMulti(query: trimmed, page: 1)
                return response.results.filter { result in
                    result.mediaType == "movie" || result.mediaType == "tv"
                }
            }.value
            guard query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
            searchResults = filtered
            prefetchResults(filtered)
            if !filtered.isEmpty && trimmed.count >= 2 {
                recentSearches = RecentSearchStore.add(trimmed)
            }
        } catch {
            self.error = error.localizedDescription
        }

        isSearching = false
    }

    @MainActor
    func selectRecentSearch(_ term: String) {
        searchTask?.cancel()
        query = term
    }

    @MainActor
    func recordSelection(_ term: String) {
        recentSearches = RecentSearchStore.add(term)
    }

    @MainActor
    func clearRecentSearches() {
        RecentSearchStore.clear()
        recentSearches = []
    }

    /// Clears the search state.
    @MainActor
    func clearSearch() {
        searchTask?.cancel()
        query = ""
        searchResults = []
        isSearching = false
        error = nil
    }

    @MainActor
    private func prefetchResults(_ results: [TMDBSearchResult]) {
        let urls = results.prefix(16).compactMap {
            service.imageURL(path: $0.backdropPath ?? $0.posterPath, size: "w780")
        }
        AuraImageCache.shared.prefetch(urls: urls, targetSize: CGSize(width: 380, height: 214))
    }

    @MainActor
    func stopPrefetching() {
        searchTask?.cancel()
        let urls = searchResults.prefix(16).compactMap {
            service.imageURL(path: $0.backdropPath ?? $0.posterPath, size: "w780")
        }
        AuraImageCache.shared.stopPrefetching(urls: urls, targetSize: CGSize(width: 380, height: 214))
    }

    // MARK: - Private

    private func handleQueryChange() {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            searchResults = []
            isSearching = false
            error = nil
            return
        }

        let delay = debounceInterval
        searchTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                // Task was cancelled during debounce — do nothing
                return
            }

            // Double-check this is still the current task
            guard let self, !Task.isCancelled else { return }
            await self.search()
        }
    }
}
