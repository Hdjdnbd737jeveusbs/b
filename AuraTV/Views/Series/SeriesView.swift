import SwiftUI
import SwiftData

// MARK: - Series View (16:9 Title Cards Grid with Safe-Area Clearance)

struct SeriesView: View {
    @Query private var settingsList: [AppSettings]
    @Query private var artworkOverrides: [CustomArtwork]
    let viewModel: SeriesViewModel
    @State private var navMemory = AuraNavigationMemory.shared

    init(viewModel: SeriesViewModel = SeriesViewModel()) {
        self.viewModel = viewModel
    }

    private var backgroundStyle: String {
        settingsList.first?.backgroundStyle ?? "Soft Glow"
    }

    private var customBackdrops: [Int: String] {
        Dictionary(
            artworkOverrides.filter { $0.mediaType == "series" }.compactMap { item in
                item.customBackdropPath.map { (item.tmdbId, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontalInset: CGFloat = 80
            let cardWidth: CGFloat = 400
            let spacing: CGFloat = 32
            let availableWidth = max(geometry.size.width - (horizontalInset * 2), cardWidth)
            let columnCount = max(1, Int((availableWidth + spacing) / (cardWidth + spacing)))
            let gridColumns = Array(repeating: GridItem(.fixed(cardWidth), spacing: spacing), count: columnCount)
            let currentSeries = viewModel.series(for: viewModel.selectedCategory)

            ZStack {
                ambientBackdropView

                // Content pushed clearly below the floating tvOS sidebar pill (< Series)
                VStack(alignment: .leading, spacing: 28) {
                    categoryBar
                        .padding(.horizontal, horizontalInset)
                        .padding(.top, 114)
                        .focusSection()

                    ScrollViewReader { scrollProxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVGrid(columns: gridColumns, spacing: 36) {
                                ForEach(Array(currentSeries.enumerated()), id: \.element.id) { index, series in
                                    SeriesCardView(
                                        series: series,
                                        overrideBackdropPath: customBackdrops[series.id],
                                        cardWidth: cardWidth,
                                        isFirstInRow: index % columnCount == 0,
                                        memoryTabKey: "Series"
                                    )
                                    .equatable()
                                    .id("series_\(series.id)")
                                }
                            }
                            .padding(.horizontal, horizontalInset)
                            .padding(.top, 8)
                            .padding(.bottom, 60)
                        }
                        .focusSection()
                        .onChange(of: navMemory.restoreTick(for: "Series")) { _, _ in
                            if let scrollTarget = AuraNavigationMemory.shared.lastScrollId(for: "Series") {
                                scrollProxy.scrollTo(scrollTarget, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.loadSeries()
            if let first = viewModel.series(for: viewModel.selectedCategory).first ?? viewModel.popularSeries.first {
                AppThemeCoordinator.shared.updateFocusedArtwork(
                    posterPath: first.posterPath,
                    backdropPath: customBackdrops[first.id] ?? first.backdropPath
                )
            }
        }
        .onChange(of: viewModel.selectedCategory) { _, newCategory in
            viewModel.prefetchSeries(Array(viewModel.series(for: newCategory).prefix(20)))
        }
        .onDisappear {
            viewModel.stopPrefetchingCurrent()
        }
    }

    // MARK: - Ambient Backdrop

    @ViewBuilder
    private var ambientBackdropView: some View {
        let targetSeries = viewModel.series(for: viewModel.selectedCategory).first ?? viewModel.popularSeries.first
        let fallbackPath = targetSeries.flatMap { customBackdrops[$0.id] ?? $0.backdropPath ?? $0.posterPath }
        AuraDynamicBackgroundView(
            styleSetting: backgroundStyle,
            fallbackBackdropURL: TMDBService.shared.imageURL(path: fallbackPath, size: "w780")
        )
    }

    // MARK: - Scaled 56pt Category Bar (Isolated Leaf Focus)

    @ViewBuilder
    private var categoryBar: some View {
        HStack(spacing: 20) {
            ForEach(SeriesCategory.allCases) { category in
                SeriesCategoryPillButton(
                    title: category.rawValue,
                    isSelected: viewModel.selectedCategory == category,
                    isFirst: category == SeriesCategory.allCases.first,
                    itemId: "series_cat_\(category.rawValue)"
                ) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                        viewModel.selectedCategory = category
                    }
                }
            }
        }
    }
}

private struct SeriesCategoryPillButton: View {
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
                AuraNavigationMemory.shared.recordFocus(tab: "Series", itemId: itemId)
            }
        }
        .onChange(of: navMemory.restoreTick(for: "Series")) { _, _ in
            if AuraNavigationMemory.shared.lastFocusedId(for: "Series") == itemId {
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
        }
    }
}
