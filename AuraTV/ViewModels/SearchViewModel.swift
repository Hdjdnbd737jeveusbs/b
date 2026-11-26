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
    var isSearching: Bool = false
    var error: String?

    // MARK: - Debounce

    private var searchTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(500)

    // MARK: - Dependencies

    private let service = TMDBService.shared

    // MARK: - Search

    /// Performs a debounced multi-search against TMDB.
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
            let response = try await service.searchMulti(query: trimmed, page: 1)
            guard !Task.isCancelled, trimmed == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            // Filter out "person" results — keep only movie and tv
            searchResults = response.results.filter { result in
                result.mediaType == "movie" || result.mediaType == "tv"
            }
        } catch {
            guard !Task.isCancelled, trimmed == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            self.error = error.localizedDescription
        }

        isSearching = false
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
