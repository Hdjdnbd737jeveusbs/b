import SwiftUI
import SwiftData

// MARK: - Collections View (User Watchlist)

struct CollectionsView: View {
    @Query(sort: \WatchlistItem.addedDate, order: .reverse) private var watchlist: [WatchlistItem]
    @Query private var settingsList: [AppSettings]
    @Query private var artworkOverrides: [CustomArtwork]
    @Environment(\.modelContext) private var modelContext
    @State private var navMemory = AuraNavigationMemory.shared

    private var posterOverrideMap: [String: String] {
        Dictionary(
            artworkOverrides.compactMap { item in
                item.customPosterPath.map { (item.key, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontalInset: CGFloat = 80
            let cardWidth: CGFloat = 260
            let spacing: CGFloat = 32
            let availableWidth = max(geometry.size.width - (horizontalInset * 2), cardWidth)
            let columnCount = max(1, Int((availableWidth + spacing) / (cardWidth + spacing)))
            let gridColumns = Array(repeating: GridItem(.fixed(cardWidth), spacing: spacing), count: columnCount)

            ZStack {
                AuraDynamicBackgroundView(styleSetting: settingsList.first?.backgroundStyle ?? "Soft Glow")

                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Collections")
                                .font(.system(size: 52, weight: .bold))
                                .foregroundStyle(.white)

                            Text("Watchlist (\(watchlist.count) items)")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.auraSecondaryText)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, horizontalInset)
                    .padding(.top, 114)

                    // Content
                    if watchlist.isEmpty {
                        emptyWatchlistView
                            .focusSection()
                    } else {
                        ScrollViewReader { scrollProxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVGrid(columns: gridColumns, spacing: 36) {
                                    ForEach(Array(watchlist.enumerated()), id: \.element.persistentModelID) { index, item in
                                        let key = CustomArtwork.makeKey(tmdbId: item.tmdbId, mediaType: item.mediaType)
                                        WatchlistCard(
                                            item: item,
                                            overridePosterPath: posterOverrideMap[key],
                                            isFirstInRow: index % columnCount == 0
                                        )
                                        .equatable()
                                        .id("collection_\(key)")
                                    }
                                }
                                .padding(.horizontal, horizontalInset)
                                .padding(.bottom, 60)
                            }
                            .focusSection()
                            .onChange(of: navMemory.restoreTick(for: "Collections")) { _, _ in
                                if let scrollTarget = AuraNavigationMemory.shared.lastScrollId(for: "Collections") {
                                    scrollProxy.scrollTo(scrollTarget, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyWatchlistView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 64))
                .foregroundStyle(Color.auraSecondaryText.opacity(0.5))

            Text("Your Watchlist is Empty")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)

            Text("Browse movies and series, then click the + button to save them here.")
                .font(.system(size: 17))
                .foregroundStyle(Color.auraSecondaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .auraLeftEdgeSidebarTrigger()
    }
}

// MARK: - Watchlist Card

private struct WatchlistCard: View, Equatable {
    let item: WatchlistItem
    var overridePosterPath: String? = nil
    var isFirstInRow: Bool = false

    @FocusState private var isFocused: Bool
    @State private var navMemory = AuraNavigationMemory.shared

    private var focusId: String {
        "collection_\(CustomArtwork.makeKey(tmdbId: item.tmdbId, mediaType: item.mediaType))"
    }

    static func == (lhs: WatchlistCard, rhs: WatchlistCard) -> Bool {
        lhs.item.tmdbId == rhs.item.tmdbId &&
        lhs.item.mediaType == rhs.item.mediaType &&
        lhs.item.title == rhs.item.title &&
        lhs.overridePosterPath == rhs.overridePosterPath &&
        lhs.isFirstInRow == rhs.isFirstInRow
    }

    var body: some View {
        NavigationLink(destination: destinationView) {
            VStack(alignment: .leading, spacing: 10) {
                // Poster
                ZStack(alignment: .topTrailing) {
                    if let path = overridePosterPath ?? item.posterPath ?? item.backdropPath,
                       let url = TMDBService.shared.imageURL(path: path, size: "w500") {
                        AuraCachedImage(url: url, targetSize: CGSize(width: 260, height: 390)) { image in
                            image
                                .resizable()
                                .aspectRatio(2/3, contentMode: .fill)
                                .frame(width: 260, height: 390)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        } placeholder: {
                            placeholder
                        }
                    } else {
                        placeholder
                    }

                    // Media badge
                    Text(item.mediaType == "series" ? "SERIES" : item.mediaType.uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 5))
                        .padding(10)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isFocused ? Color.white : Color.white.opacity(0.14), lineWidth: isFocused ? 3.5 : 1)
                )

                // Title
                Text(item.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: 260, alignment: .leading)
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
                AuraNavigationMemory.shared.recordFocus(tab: "Collections", itemId: focusId)
            }
        }
        .onChange(of: navMemory.restoreTick(for: "Collections")) { _, _ in
            if AuraNavigationMemory.shared.lastFocusedId(for: "Collections") == focusId {
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
        }
        .modifier(MediaPosterContextMenuModifier(
            tmdbId: item.tmdbId,
            mediaType: item.mediaType,
            title: item.title,
            posterPath: overridePosterPath ?? item.posterPath,
            backdropPath: item.backdropPath,
            initialWatched: false
        ))
    }

    @ViewBuilder
    private var destinationView: some View {
        if item.mediaType == "series" {
            SeriesDetailView(tmdbId: item.tmdbId)
        } else {
            MovieDetailView(tmdbId: item.tmdbId)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.auraCardSurface)
            .frame(width: 260, height: 390)
            .overlay {
                Image(systemName: item.mediaType == "series" ? "tv" : "film")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.25))
            }
    }
}
