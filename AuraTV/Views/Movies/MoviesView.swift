import SwiftUI
import SwiftData

// MARK: - Movies View (Ambient Backdrop + Category Grid with Safe-Area Clearance)

struct MoviesView: View {
    @Query private var historyItems: [WatchHistory]
    @Query private var settingsList: [AppSettings]
    @Query private var artworkOverrides: [CustomArtwork]

    @Bindable var viewModel: MoviesViewModel
    @State private var navMemory = AuraNavigationMemory.shared

    init(viewModel: MoviesViewModel = MoviesViewModel()) {
        self.viewModel = viewModel
    }

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
            let horizontalInset: CGFloat = 80
            let cardWidth: CGFloat = 268
            let spacing: CGFloat = 32
            let availableWidth = max(geometry.size.width - (horizontalInset * 2), cardWidth)
            let columnCount = max(1, Int((availableWidth + spacing) / (cardWidth + spacing)))
            let gridColumns = Array(repeating: GridItem(.fixed(cardWidth), spacing: spacing), count: columnCount)
            let currentMovies = viewModel.movies(for: viewModel.selectedCategory)

            ZStack {
                ambientBackdropView

                // Content pushed clearly below the floating tvOS sidebar pill (< Movies)
                VStack(alignment: .leading, spacing: 28) {
                    categoryBar
                        .padding(.horizontal, horizontalInset)
                        .padding(.top, 114)
                        .focusSection()

                    ScrollViewReader { scrollProxy in
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
                                        .id("movie_\(movie.id)")
                                    }
                                }
                                .padding(.horizontal, horizontalInset)
                                .padding(.top, 8)
                                .padding(.bottom, 60)
                            } else {
                                LazyVGrid(columns: gridColumns, spacing: 36) {
                                    ForEach(Array(currentMovies.enumerated()), id: \.element.id) { index, movie in
                                        PosterCardView(
                                            movie: movie,
                                            overridePosterPath: customPosters[movie.id],
                                            isWatched: watchedMovieIds.contains(movie.id),
                                            showWatchedBadge: showWatchedIndicators,
                                            isFirstInRow: index % columnCount == 0,
                                            posterWidth: cardWidth,
                                            memoryTabKey: "Movies"
                                        )
                                        .equatable()
                                        .id("movie_\(movie.id)")
                                    }
                                }
                                .padding(.horizontal, horizontalInset)
                                .padding(.top, 8)
                                .padding(.bottom, 60)
                            }
                        }
                        .focusSection()
                        .onChange(of: navMemory.restoreTick(for: "Movies")) { _, _ in
                            if let scrollTarget = AuraNavigationMemory.shared.lastScrollId(for: "Movies") {
                                scrollProxy.scrollTo(scrollTarget, anchor: .center)
                            }
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
        .onChange(of: viewModel.selectedCategory) { _, newCategory in
            viewModel.prefetchMovies(Array(viewModel.movies(for: newCategory).prefix(20)))
        }
        .onDisappear {
            viewModel.stopPrefetchingCurrent()
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

    // MARK: - Scaled 56pt Category Bar (Isolated Leaf Focus)

    @ViewBuilder
    private var categoryBar: some View {
        HStack(spacing: 20) {
            ForEach(MovieCategory.allCases) { category in
                MovieCategoryPillButton(
                    title: category.rawValue,
                    isSelected: viewModel.selectedCategory == category,
                    isFirst: category == MovieCategory.allCases.first,
                    itemId: "movie_cat_\(category.rawValue)"
                ) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                        viewModel.selectedCategory = category
                    }
                }
            }
        }
    }
}

private struct MovieCategoryPillButton: View {
    let title: String
    let isSelected: Bool
    let isFirst: Bool
    let itemId: String
    let action: () -> Void

    @FocusState private var isFocused: Bool
    @State private var navMemory = AuraNavigationMemory.shared

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isSelected || isFocused ? Color.black : Color.white)
                .padding(.horizontal, 28)
                .frame(height: 56)
                .background((isSelected || isFocused) ? Color.white : Color.auraCardSurface)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isFocused ? Color.white : Color.white.opacity(0.14), lineWidth: isFocused ? 2.5 : 1)
                )
                .contentShape(Capsule())
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
        .auraLeftEdgeSidebarTrigger(isFirst)
        .onChange(of: isFocused) { _, focused in
            if focused {
                AuraNavigationMemory.shared.recordFocus(tab: "Movies", itemId: itemId)
            }
        }
        .onChange(of: navMemory.restoreTick(for: "Movies")) { _, _ in
            if AuraNavigationMemory.shared.lastFocusedId(for: "Movies") == itemId {
                DispatchQueue.main.async {
                    isFocused = true
                }
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
    @State private var navMemory = AuraNavigationMemory.shared

    private var focusId: String { "movie_\(movie.id)" }

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
            .background(Color.white.opacity(isFocused ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.14), lineWidth: isFocused ? 2.5 : 1)
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
        .auraLeftEdgeSidebarTrigger()
        .onChange(of: isFocused) { _, focused in
            if focused {
                AuraNavigationMemory.shared.recordFocus(tab: "Movies", itemId: focusId)
                AppThemeCoordinator.shared.updateFocusedArtwork(
                    posterPath: overridePosterPath ?? movie.posterPath,
                    backdropPath: overrideBackdropPath ?? movie.backdropPath
                )
            }
        }
        .onChange(of: navMemory.restoreTick(for: "Movies")) { _, _ in
            if AuraNavigationMemory.shared.lastFocusedId(for: "Movies") == focusId {
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
        }
        .modifier(MediaPosterContextMenuModifier(
            tmdbId: movie.id,
            mediaType: "movie",
            title: movie.title,
            posterPath: overridePosterPath ?? movie.posterPath,
            backdropPath: overrideBackdropPath ?? movie.backdropPath,
            initialWatched: isWatched
        ))
    }
}
