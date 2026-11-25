import SwiftUI

// MARK: - Search View (tvOS Native Search)

struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    @FocusState private var isFieldFocused: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 210, maximum: 240), spacing: 28)
    ]

    var body: some View {
        ZStack {
            Color.auraBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                // Search Input Header
                HStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.auraSecondaryText)

                    TextField("Search movies, series...", text: $viewModel.query)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                        .focused($isFieldFocused)

                    if !viewModel.query.isEmpty {
                        Button(action: { viewModel.clearSearch() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.auraSecondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color.auraSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 75)
                .padding(.top, 84)

                // Results or Empty State
                if viewModel.isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tint(.white)
                } else if viewModel.searchResults.isEmpty {
                    emptyStateView
                } else {
                    resultsGrid
                }
            }
        }
        .defaultFocus($isFieldFocused, true)
    }

    // MARK: - Results Grid

    @ViewBuilder
    private var resultsGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 32) {
                ForEach(viewModel.searchResults) { result in
                    SearchResultCard(result: result)
                }
            }
            .padding(.horizontal, 75)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: viewModel.query.isEmpty ? "sparkle.magnifyingglass" : "questionmark.folder")
                .font(.system(size: 64))
                .foregroundStyle(Color.auraSecondaryText.opacity(0.6))

            Text(viewModel.query.isEmpty ? "Discover Movies & Series" : "No results for \"\(viewModel.query)\"")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)

            Text(viewModel.query.isEmpty ? "Type a title, genre, or actor to search TMDB." : "Try searching with a different spelling or keyword.")
                .font(.system(size: 16))
                .foregroundStyle(Color.auraSecondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Search Result Card

private struct SearchResultCard: View {
    let result: TMDBSearchResult

    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationLink(destination: destinationView) {
            VStack(alignment: .leading, spacing: 10) {
                // Poster image
                ZStack(alignment: .topTrailing) {
                    if let path = result.posterPath ?? result.backdropPath,
                       let url = TMDBService.shared.imageURL(path: path, size: "w500") {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(2/3, contentMode: .fill)
                                    .frame(width: 220, height: 330)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            default:
                                placeholder
                            }
                        }
                    } else {
                        placeholder
                    }

                    // Media Type Badge ("Movie" or "TV")
                    Text(result.isMovie ? "MOVIE" : "SERIES")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 5))
                        .padding(8)
                }

                // Title & Date
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.displayTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if result.displayDate.count >= 4 {
                        Text(String(result.displayDate.prefix(4)))
                            .font(.system(size: 14))
                            .foregroundStyle(Color.auraSecondaryText)
                    }
                }
                .frame(width: 220, alignment: .leading)
            }
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .shadow(
                color: isFocused ? Color.auraAccent.opacity(0.5) : Color.black.opacity(0.3),
                radius: isFocused ? 20 : 6,
                y: isFocused ? 10 : 3
            )
            .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }

    @ViewBuilder
    private var destinationView: some View {
        if result.isMovie {
            MovieDetailView(tmdbId: result.id)
        } else {
            SeriesDetailView(tmdbId: result.id)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.auraSurface)
            .frame(width: 220, height: 330)
            .overlay {
                Image(systemName: result.isMovie ? "film" : "tv")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.25))
            }
    }
}
