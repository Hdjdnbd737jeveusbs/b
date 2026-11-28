import SwiftUI
import SwiftData

// MARK: - Search View (300ms Off-MainActor Instant Search + Recent History + Quick Jump)

struct SearchView: View {
    @Query private var settingsList: [AppSettings]
    @Bindable var viewModel: SearchViewModel
    @State private var navMemory = AuraNavigationMemory.shared
    @FocusState private var isFieldFocused: Bool
    @State private var jumpToFirstResultTick: Int = 0

    init(viewModel: SearchViewModel = SearchViewModel()) {
        self.viewModel = viewModel
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontalInset: CGFloat = 80
            let cardWidth: CGFloat = 380
            let spacing: CGFloat = 32
            let availableWidth = max(geometry.size.width - (horizontalInset * 2), cardWidth)
            let columnCount = max(1, Int((availableWidth + spacing) / (cardWidth + spacing)))
            let gridColumns = Array(repeating: GridItem(.fixed(cardWidth), spacing: spacing), count: columnCount)

            ZStack {
                AuraDynamicBackgroundView(styleSetting: settingsList.first?.backgroundStyle ?? "Soft Glow")

                VStack(alignment: .leading, spacing: 26) {
                    // Search Input Header
                    HStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Color.auraSecondaryText)

                        TextField("Search movies, series...", text: $viewModel.query)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.white)
                            .focused($isFieldFocused)
                            .auraLeftEdgeSidebarTrigger()

                        if !viewModel.searchResults.isEmpty {
                            Button {
                                jumpToFirstResultTick += 1
                            } label: {
                                Text("Results (\(viewModel.searchResults.count))")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 18)
                                    .frame(height: 46)
                                    .background(Color.white, in: Capsule())
                            }
                            .buttonStyle(AuraButtonStyle())
                            .focusEffectDisabled()
                        }

                        if !viewModel.query.isEmpty {
                            Button(action: { viewModel.clearSearch() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.auraSecondaryText)
                            }
                            .buttonStyle(AuraButtonStyle())
                            .focusEffectDisabled()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Color.auraCardSurface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .padding(.horizontal, horizontalInset)
                    .padding(.top, 114)
                    .focusSection()

                    // Recent Search History Row when query is empty
                    if viewModel.query.isEmpty && !viewModel.recentSearches.isEmpty {
                        recentSearchesBar
                            .padding(.horizontal, horizontalInset)
                            .focusSection()
                    }

                    // Results or Empty State
                    if viewModel.isSearching {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .tint(.white)
                    } else if viewModel.searchResults.isEmpty {
                        emptyStateView
                    } else {
                        resultsGrid(
                            columnCount: columnCount,
                            gridColumns: gridColumns,
                            horizontalInset: horizontalInset,
                            cardWidth: cardWidth
                        )
                        .focusSection()
                    }
                }
            }
        }
        .defaultFocus($isFieldFocused, true)
        .onDisappear {
            viewModel.stopPrefetching()
        }
    }

    // MARK: - Recent Searches Row

    @ViewBuilder
    private var recentSearchesBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent Searches")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                SearchHistoryActionButton(title: "Clear", systemName: "trash") {
                    viewModel.clearRecentSearches()
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(viewModel.recentSearches.enumerated()), id: \.offset) { index, term in
                        SearchHistoryActionButton(
                            title: term,
                            systemName: "clock.arrow.circlepath",
                            isFirst: index == 0
                        ) {
                            viewModel.selectRecentSearch(term)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Results Grid (16:9 Cards + Focus Memory)

    @ViewBuilder
    private func resultsGrid(
        columnCount: Int,
        gridColumns: [GridItem],
        horizontalInset: CGFloat,
        cardWidth: CGFloat
    ) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: gridColumns, spacing: 36) {
                    let firstResult = viewModel.searchResults.first
                    ForEach(Array(viewModel.searchResults.enumerated()), id: \.element.id) { index, result in
                        SearchResultCard(
                            result: result,
                            cardWidth: cardWidth,
                            isFirstInRow: index % columnCount == 0,
                            isFirstOverall: result.id == firstResult?.id && result.mediaType == firstResult?.mediaType,
                            jumpTick: jumpToFirstResultTick,
                            onSelect: {
                                viewModel.recordSelection(viewModel.query)
                            }
                        )
                        .equatable()
                        .id("search_\(result.mediaType ?? "m")_\(result.id)")
                    }
                }
                .padding(.horizontal, horizontalInset)
                .padding(.bottom, 60)
            }
            .onChange(of: navMemory.restoreTick(for: "Search")) { _, _ in
                if let scrollTarget = AuraNavigationMemory.shared.lastScrollId(for: "Search") {
                    scrollProxy.scrollTo(scrollTarget, anchor: .center)
                }
            }
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
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)

            Text(viewModel.query.isEmpty ? "Type a title to search instantly across TMDB." : "Try searching with a different spelling or keyword.")
                .font(.system(size: 22))
                .foregroundStyle(Color.auraSecondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SearchHistoryActionButton: View {
    let title: String
    let systemName: String
    var isFirst: Bool = false
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .padding(.horizontal, 24)
            .frame(height: 52)
            .background(isFocused ? Color.white : Color.auraCardSurface, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.14), lineWidth: isFocused ? 2 : 1)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
        .auraLeftEdgeSidebarTrigger(isFirst)
    }
}

// MARK: - Search Result Card (16:9 Landscape Card + 22pt/18pt Typography)

private struct SearchResultCard: View, Equatable {
    let result: TMDBSearchResult
    var cardWidth: CGFloat = 380
    var isFirstInRow: Bool = false
    var isFirstOverall: Bool = false
    var jumpTick: Int = 0
    var onSelect: (() -> Void)? = nil

    @FocusState private var isFocused: Bool
    @State private var navMemory = AuraNavigationMemory.shared

    private var cardHeight: CGFloat { (cardWidth * 9.0 / 16.0).rounded() }
    private var focusId: String { "search_\(result.mediaType ?? "m")_\(result.id)" }

    static func == (lhs: SearchResultCard, rhs: SearchResultCard) -> Bool {
        lhs.result.id == rhs.result.id &&
        lhs.result.mediaType == rhs.result.mediaType &&
        lhs.cardWidth == rhs.cardWidth &&
        lhs.isFirstInRow == rhs.isFirstInRow &&
        lhs.isFirstOverall == rhs.isFirstOverall &&
        lhs.jumpTick == rhs.jumpTick
    }

    private var subtitleLine: String {
        var parts: [String] = [result.isMovie ? "Movie" : "Series"]
        if result.displayDate.count >= 4 {
            parts.append(String(result.displayDate.prefix(4)))
        }
        if let vote = result.voteAverage, vote > 0 {
            parts.append("★ \(String(format: "%.1f", vote))")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationLink(destination: destinationView) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    if let path = result.backdropPath ?? result.posterPath,
                       let url = TMDBService.shared.imageURL(path: path, size: "w780") {
                        AuraCachedImage(url: url, targetSize: CGSize(width: cardWidth, height: cardHeight)) { image in
                            image
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fill)
                                .frame(width: cardWidth, height: cardHeight)
                                .clipped()
                        } placeholder: {
                            placeholder
                        }
                    } else {
                        placeholder
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isFocused ? Color.white : Color.white.opacity(0.14), lineWidth: isFocused ? 3.5 : 1)
                )

                // Title & Subtitle/Rating underneath (22pt Semibold / 18pt Regular)
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.displayTitle)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(subtitleLine)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255))
                        .lineLimit(1)
                }
                .frame(width: cardWidth, alignment: .leading)
            }
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
        .auraLeftEdgeSidebarTrigger(isFirstInRow)
        .onChange(of: isFocused) { _, focused in
            if focused {
                AuraNavigationMemory.shared.recordFocus(tab: "Search", itemId: focusId)
            }
        }
        .onChange(of: jumpTick) { _, _ in
            if isFirstOverall {
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
        }
        .onChange(of: navMemory.restoreTick(for: "Search")) { _, _ in
            if AuraNavigationMemory.shared.lastFocusedId(for: "Search") == focusId {
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
        }
        .simultaneousGesture(TapGesture().onEnded { onSelect?() })
        .modifier(MediaPosterContextMenuModifier(
            tmdbId: result.id,
            mediaType: result.isMovie ? "movie" : "series",
            title: result.displayTitle,
            posterPath: result.posterPath,
            backdropPath: result.backdropPath,
            initialWatched: false
        ))
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
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.auraCardSurface)
            .frame(width: cardWidth, height: cardHeight)
            .overlay {
                Image(systemName: result.isMovie ? "film" : "tv")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.25))
            }
    }
}
