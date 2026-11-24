import SwiftUI
import SwiftData

// MARK: - Collections View (User Watchlist)

struct CollectionsView: View {
    @Query(sort: \WatchlistItem.addedDate, order: .reverse) private var watchlist: [WatchlistItem]
    @Environment(\.modelContext) private var modelContext

    private let columns = [
        GridItem(.adaptive(minimum: 210, maximum: 240), spacing: 28)
    ]

    var body: some View {
        ZStack {
            Color.auraBackground.ignoresSafeArea()

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
                .padding(.horizontal, 50)
                .padding(.top, 24)

                // Content
                if watchlist.isEmpty {
                    emptyWatchlistView
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: columns, spacing: 32) {
                            ForEach(watchlist) { item in
                                WatchlistCard(item: item)
                            }
                        }
                        .padding(.horizontal, 50)
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

    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationLink(destination: destinationView) {
            VStack(alignment: .leading, spacing: 10) {
                // Poster
                ZStack(alignment: .topTrailing) {
                    if let path = item.posterPath ?? item.backdropPath,
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

                    // Media badge
                    Text(item.mediaType.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 5))
                        .padding(8)
                }

                // Title
                Text(item.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
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
