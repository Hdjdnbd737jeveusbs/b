import SwiftUI

// MARK: - Continue Watching Row (16:9 Title Cards with Progress Bars)

struct ContinueWatchingRow: View {
    let items: [WatchHistory]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                // Section Header
                Text("Continue Watching")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 50)

                // Horizontal list of 16:9 cards
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 24) {
                        ForEach(items) { item in
                            ContinueWatchingCard(item: item)
                        }
                    }
                    .padding(.horizontal, 50)
                    .padding(.vertical, 16)
                }
            }
        }
    }
}

// MARK: - Continue Watching Card

private struct ContinueWatchingCard: View {
    let item: WatchHistory

    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationLink(destination: destinationView) {
            VStack(alignment: .leading, spacing: 8) {
                // 16:9 Image container with progress bar
                ZStack(alignment: .bottom) {
                    // Backdrop or episode still
                    imageContent

                    // Progress bar at bottom of card
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 4)

                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 360 * max(min(item.progress, 1.0), 0), height: 4)
                    }
                }
                .frame(width: 360, height: 202)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isFocused ? Color.white.opacity(0.8) : Color.clear, lineWidth: 2.5)
                )

                // Title and episode info below
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let epTitle = item.episodeTitle, !epTitle.isEmpty,
                       let s = item.seasonNumber, let e = item.episodeNumber {
                        Text("S\(s):E\(e) · \(epTitle)")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.auraSecondaryText)
                            .lineLimit(1)
                    } else if !item.remainingTimeFormatted.isEmpty {
                        Text("\(item.remainingTimeFormatted) left")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.auraSecondaryText)
                    }
                }
                .frame(width: 360, alignment: .leading)
            }
            .scaleEffect(isFocused ? 1.07 : 1.0)
            .shadow(
                color: isFocused ? Color.auraAccent.opacity(0.5) : Color.black.opacity(0.4),
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

    @ViewBuilder
    private var imageContent: some View {
        let imagePath = item.episodeStillPath ?? item.backdropPath ?? item.posterPath
        if let path = imagePath,
           let url = TMDBService.shared.imageURL(path: path, size: "w780") {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(width: 360, height: 202)
                        .clipped()
                case .failure, .empty:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.auraSurface)
            .frame(width: 360, height: 202)
            .overlay {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.25))
            }
    }
}
