import SwiftUI
import SwiftData

// MARK: - Movies View (Ambient Backdrop + Category Grid with Safe-Area Clearance)

struct MoviesView: View {
    @Query private var historyItems: [WatchHistory]
    @Query private var settingsList: [AppSettings]

    @State private var viewModel = MoviesViewModel()
    @State private var focusedMovie: TMDBMovie?
    @FocusState private var focusedCategory: MovieCategory?
    @FocusState private var focusedMovieId: Int?

    private let columns = [
        GridItem(.adaptive(minimum: 205, maximum: 230), spacing: 26)
    ]

    private var watchedMovieIds: Set<Int> {
        Set(historyItems.filter { $0.mediaType == "movie" && $0.isCompleted }.map(\.tmdbId))
    }

    private var showWatchedIndicators: Bool {
        settingsList.first?.showWatchedIndicators ?? true
    }

    var body: some View {
        ZStack {
            // Ambient Backdrop of focused movie
            ambientBackdropView

            // Content pushed clearly below the floating tvOS sidebar pill (< Movies)
            VStack(alignment: .leading, spacing: 26) {
                categoryBar
                    .padding(.horizontal, 75)
                    .padding(.top, 84)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 32) {
                        ForEach(viewModel.movies(for: viewModel.selectedCategory)) { movie in
                            PosterCardView(
                                movie: movie,
                                isWatched: watchedMovieIds.contains(movie.id),
                                showWatchedBadge: showWatchedIndicators
                            )
                            .focused($focusedMovieId, equals: movie.id)
                        }
                    }
                    .padding(.horizontal, 75)
                    .padding(.top, 8)
                    .padding(.bottom, 60)
                }
            }
        }
        .onChange(of: focusedMovieId) { _, newId in
            guard let newId else { return }
            focusedMovie = viewModel.movies(for: viewModel.selectedCategory).first { $0.id == newId }
        }
        .task {
            await viewModel.loadMovies()
        }
    }

    // MARK: - Ambient Backdrop

    @ViewBuilder
    private var ambientBackdropView: some View {
        ZStack {
            Color.auraBackground.ignoresSafeArea()

            if let path = focusedMovie?.backdropPath ?? viewModel.popularMovies.first?.backdropPath,
               let url = TMDBService.shared.imageURL(path: path, size: "w1280") {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .ignoresSafeArea()
                            .blur(radius: 40)
                            .opacity(0.32)
                            .overlay(Color.auraBackground.opacity(0.65))
                    }
                }
            }
        }
    }

    // MARK: - Category Bar

    @ViewBuilder
    private var categoryBar: some View {
        HStack(spacing: 22) {
            ForEach(MovieCategory.allCases) { category in
                let isSelected = viewModel.selectedCategory == category
                let isFocused = focusedCategory == category

                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        viewModel.selectedCategory = category
                    }
                }) {
                    Text(category.rawValue)
                        .font(.system(size: 19, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected || isFocused ? Color.black : Color.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                        .background(
                            (isSelected || isFocused)
                            ? Color.white
                            : Color.white.opacity(0.1)
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(isFocused ? Color.white : Color.white.opacity(0.14), lineWidth: isFocused ? 2 : 1)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .focused($focusedCategory, equals: category)
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(.easeOut(duration: 0.16), value: focusedCategory)
            }
        }
    }
}
