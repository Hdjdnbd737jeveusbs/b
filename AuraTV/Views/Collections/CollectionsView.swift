import SwiftUI
import SwiftData

// MARK: - Collections View (User Watchlist)

struct CollectionsView: View {
    @Query(sort: \WatchlistItem.addedDate, order: .reverse) private var watchlist: [WatchlistItem]
    @Query private var settingsList: [AppSettings]
    @Query private var artworkOverrides: [CustomArtwork]
    @Environment(\.modelContext) private var modelContext

    private var posterOverrideMap: [String: String] {
        Dictionary(
            artworkOverrides.compactMap { item in
                item.customPosterPath.map { (item.key, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private let columns = [
        GridItem(.adaptive(minimum: 210, maximum: 240), spacing: 28)
    ]

    var body: some View {
        ZStack {
            AuraDynamicBackgroundView(styleSetting: settingsList.first?.backgroundStyle ?? "Soft Glow")

            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Collections")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(.white)

                        Text("Watchlist (\(watchlist.count) items)")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.auraSecondaryText)
                    }
                    Spacer()
                }
                .padding(.horizontal, 75)
                .padding(.top, 84)

                // Content
                if watchlist.isEmpty {
                    emptyWatchlistView
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: columns, spacing: 32) {
                            ForEach(watchlist) { item in
                                let key = CustomArtwork.makeKey(tmdbId: item.tmdbId, mediaType: item.mediaType)
                                WatchlistCard(item: item, overridePosterPath: posterOverrideMap[key])
                            }
                        }
                        .padding(.horizontal, 75)
                        .padding(.bottom, 60)
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
    }
}

// MARK: - Watchlist Card

private struct WatchlistCard: View {
    let item: WatchlistItem
    var overridePosterPath: String? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationLink(destination: destinationView) {
            VStack(alignment: .leading, spacing: 10) {
                // Poster
                ZStack(alignment: .topTrailing) {
                    if let path = overridePosterPath ?? item.posterPath ?? item.backdropPath,
                       let url = TMDBService.shared.imageURL(path: path, size: "w500") {
                        AuraCachedImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(2/3, contentMode: .fill)
                                .frame(width: 220, height: 330)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        } placeholder: {
                            placeholder
                        }
                    } else {
                        placeholder
                    }

                    // Media badge
                    Text(item.mediaType == "series" ? "SERIES" : item.mediaType.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 5))
                        .padding(8)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 3.5 : 1)
                )

                // Title
                Text(item.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: 220, alignment: .leading)
            }
            .scaleEffect(isFocused ? 1.07 : 1.0)
            .shadow(
                color: isFocused ? Color.white.opacity(0.22) : Color.black.opacity(0.35),
                radius: isFocused ? 20 : 6,
                y: isFocused ? 10 : 3
            )
            .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
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
            .fill(Color.auraSurface)
            .frame(width: 220, height: 330)
            .overlay {
                Image(systemName: item.mediaType == "series" ? "tv" : "film")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.25))
            }
    }
}
