import SwiftUI

// MARK: - Continue Watching Row (16:9 Landscape Cards with Bottom Progress Bar)

struct ContinueWatchingRow: View {
    let items: [WatchHistory]
    var backdropOverrides: [String: String] = [:]
    var autoPlayTrailersOnFocus: Bool = false

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Continue Watching")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 24) {
                        ForEach(items) { item in
                            let key = CustomArtwork.makeKey(tmdbId: item.tmdbId, mediaType: item.mediaType)
                            ContinueWatchingCard(
                                item: item,
                                overrideBackdropPath: backdropOverrides[key],
                                autoPlayTrailersOnFocus: autoPlayTrailersOnFocus
                            )
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 18)
                }
            }
        }
    }
}

// MARK: - Continue Watching Card

private struct ContinueWatchingCard: View {
    let item: WatchHistory
    var overrideBackdropPath: String? = nil
    var autoPlayTrailersOnFocus: Bool = false

    @FocusState private var isFocused: Bool
    @State private var themeCoordinator = AppThemeCoordinator.shared

    var body: some View {
        NavigationLink(destination: destinationView) {
            VStack(alignment: .leading, spacing: 10) {
                // 16:9 Image container with thin flush bottom progress bar
                ZStack(alignment: .bottom) {
                    imageContent

                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.28))
                            .frame(height: 4)

                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 340 * max(min(item.progress, 1.0), 0.04), height: 4)
                    }
                }
                .frame(width: 340, height: 191)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 3 : 1)
                )

                // Title & remaining time underneath
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(subtitleText)
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(Color.auraSecondaryText)
                        .lineLimit(1)
                }
                .frame(width: 340, alignment: .leading)
            }
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.16), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused {
                themeCoordinator.onHomeCardFocused(
                    mediaType: item.mediaType,
                    tmdbId: item.tmdbId,
                    title: item.title,
                    overview: nil,
                    posterPath: item.posterPath,
                    backdropPath: overrideBackdropPath ?? item.backdropPath ?? item.episodeStillPath,
                    releaseYear: nil,
                    voteAverage: nil,
                    autoPlayTrailers: autoPlayTrailersOnFocus
                )
            } else if autoPlayTrailersOnFocus {
                themeCoordinator.onHomeCardBlurred(mediaType: item.mediaType, tmdbId: item.tmdbId)
            }
        }
    }

    private var subtitleText: String {
        if item.mediaType == "series", let s = item.seasonNumber, let e = item.episodeNumber {
            if !item.remainingTimeFormatted.isEmpty {
                return "S\(s) • E\(e) • \(item.remainingTimeFormatted) left"
            } else if let epTitle = item.episodeTitle, !epTitle.isEmpty {
                return "S\(s) • E\(e) • \(epTitle)"
            }
            return "S\(s) • E\(e) • Next episode"
        } else if !item.remainingTimeFormatted.isEmpty {
            return "\(item.remainingTimeFormatted) left"
        }
        return "In progress"
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
        let imagePath = item.episodeStillPath ?? overrideBackdropPath ?? item.backdropPath ?? item.posterPath
        if let path = imagePath,
           let url = TMDBService.shared.imageURL(path: path, size: "w780") {
            AuraCachedImage(url: url, targetSize: CGSize(width: 340, height: 191)) { image in
                image
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(width: 340, height: 191)
                    .clipped()
            } placeholder: {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.auraSurface)
            .frame(width: 340, height: 191)
            .overlay {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 38))
                    .foregroundStyle(.white.opacity(0.25))
            }
    }
}
