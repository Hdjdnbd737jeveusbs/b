import SwiftUI
import SwiftData

// MARK: - Movies View (Ambient Backdrop + Category Grid with Safe-Area Clearance)

struct MoviesView: View {
    @Query private var historyItems: [WatchHistory]
    @Query private var settingsList: [AppSettings]
    @Query private var artworkOverrides: [CustomArtwork]

    @State private var viewModel = MoviesViewModel()
    @FocusState private var focusedCategory: MovieCategory?

    private let columns = [
        GridItem(.adaptive(minimum: 255, maximum: 280), spacing: 28)
    ]

    private var watchedMovieIds: Set<Int> {
        Set(historyItems.filter { $0.mediaType == "movie" && $0.isCompleted }.map(\.tmdbId))
    }

    private var showWatchedIndicators: Bool {
        settingsList.first?.showWatchedIndicators ?? true
    }

    private var useListLayout: Bool {
        settingsList.first?.moviesLayoutStyle == "List"
    }

    private var backgroundStyle: String {
        settingsList.first?.backgroundStyle ?? "Soft Glow"
    }

    private var customPosters: [Int: String] {
        Dictionary(
            artworkOverrides.filter { $0.mediaType == "movie" }.compactMap { item in
                item.customPosterPath.map { (item.tmdbId, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var customBackdrops: [Int: String] {
        Dictionary(
            artworkOverrides.filter { $0.mediaType == "movie" }.compactMap { item in
                item.customBackdropPath.map { (item.tmdbId, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width - 136, 255)
            let columnCount = max(1, Int((availableWidth + 28) / (255 + 28)))
            let currentMovies = viewModel.movies(for: viewModel.selectedCategory)

            ZStack {
                // Ambient Backdrop (isolated observer — grid never re-renders on focus moves)
                ambientBackdropView

                // Content pushed clearly below the floating tvOS sidebar pill (< Movies)
                VStack(alignment: .leading, spacing: 28) {
                    categoryBar
                        .padding(.horizontal, 68)
                        .padding(.top, 92)

                    ScrollView(.vertical, showsIndicators: false) {
                        if useListLayout {
                            LazyVStack(spacing: 18) {
                                ForEach(currentMovies) { movie in
                                    MovieListRowView(
                                        movie: movie,
                                        overridePosterPath: customPosters[movie.id],
                                        overrideBackdropPath: customBackdrops[movie.id],
                                        isWatched: watchedMovieIds.contains(movie.id),
                                        showWatchedBadge: showWatchedIndicators
                                    )
                                    .equatable()
                                }
                            }
                            .padding(.horizontal, 68)
                            .padding(.top, 8)
                            .padding(.bottom, 60)
                        } else {
                            LazyVGrid(columns: columns, spacing: 32) {
                                ForEach(Array(currentMovies.enumerated()), id: \.element.id) { index, movie in
                                    PosterCardView(
                                        movie: movie,
                                        overridePosterPath: customPosters[movie.id],
                                        isWatched: watchedMovieIds.contains(movie.id),
                                        showWatchedBadge: showWatchedIndicators,
                                        isFirstInRow: index % columnCount == 0
                                    )
                                    .equatable()
                                }
                            }
                            .padding(.horizontal, 68)
                            .padding(.top, 8)
                            .padding(.bottom, 60)
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.loadMovies()
            if let first = viewModel.movies(for: viewModel.selectedCategory).first ?? viewModel.popularMovies.first {
                AppThemeCoordinator.shared.updateFocusedArtwork(
                    posterPath: customPosters[first.id] ?? first.posterPath,
                    backdropPath: customBackdrops[first.id] ?? first.backdropPath
                )
            }
        }
    }

    // MARK: - Ambient Backdrop

    @ViewBuilder
    private var ambientBackdropView: some View {
        let targetMovie = viewModel.movies(for: viewModel.selectedCategory).first ?? viewModel.popularMovies.first
        let fallbackPath = targetMovie.flatMap { customBackdrops[$0.id] ?? $0.backdropPath ?? $0.posterPath }
        AuraDynamicBackgroundView(
            styleSetting: backgroundStyle,
            fallbackBackdropURL: TMDBService.shared.imageURL(path: fallbackPath, size: "w780")
        )
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
                        .font(.system(size: 26, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected || isFocused ? Color.black : Color.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
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
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()
                .focused($focusedCategory, equals: category)
                .auraLeftEdgeSidebarTrigger(category == .popular)
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(.easeOut(duration: 0.14), value: focusedCategory)
            }
        }
    }
}

private struct MovieListRowView: View, Equatable {
    let movie: TMDBMovie
    var overridePosterPath: String?
    var overrideBackdropPath: String? = nil
    let isWatched: Bool
    let showWatchedBadge: Bool

    @FocusState private var isFocused: Bool

    static func == (lhs: MovieListRowView, rhs: MovieListRowView) -> Bool {
        lhs.movie.id == rhs.movie.id &&
        lhs.overridePosterPath == rhs.overridePosterPath &&
        lhs.overrideBackdropPath == rhs.overrideBackdropPath &&
        lhs.isWatched == rhs.isWatched &&
        lhs.showWatchedBadge == rhs.showWatchedBadge
    }

    var body: some View {
        NavigationLink(destination: MovieDetailView(tmdbId: movie.id)) {
            HStack(spacing: 24) {
                if let path = overridePosterPath ?? movie.posterPath ?? movie.backdropPath,
                   let url = TMDBService.shared.imageURL(path: path, size: "w342") {
                    AuraCachedImage(url: url, targetSize: CGSize(width: 96, height: 144)) { image in
                        image
                            .resizable()
                            .aspectRatio(2 / 3, contentMode: .fill)
                            .frame(width: 96, height: 144)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.auraSurface)
                            .frame(width: 96, height: 144)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.auraSurface)
                        .frame(width: 96, height: 144)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text(movie.title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if isWatched && showWatchedBadge {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                        }
                    }

                    HStack(spacing: 12) {
                        if let date = movie.releaseDate, date.count >= 4 {
                            Text(String(date.prefix(4)))
                        }
                        if let vote = movie.voteAverage, vote > 0 {
                            Label(String(format: "%.1f", vote), systemImage: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.auraSecondaryText)

                    if let overview = movie.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.74))
                            .lineLimit(2)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(18)
            .background(Color.white.opacity(isFocused ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 2.5 : 1)
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
        .auraLeftEdgeSidebarTrigger()
        .onChange(of: isFocused) { _, focused in
            if focused {
                AppThemeCoordinator.shared.updateFocusedArtwork(
                    posterPath: overridePosterPath ?? movie.posterPath,
                    backdropPath: overrideBackdropPath ?? movie.backdropPath
                )
            }
        }
    }
}
