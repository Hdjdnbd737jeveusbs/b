import SwiftUI

// MARK: - Series Poster Card View (Clean 2:3 Portrait Card for Home Row)

struct SeriesPosterCardView: View {
    let series: TMDBSeries
    var overridePosterPath: String? = nil
    var isWatched: Bool = false
    var showWatchedBadge: Bool = true
    var autoPlayTrailersOnFocus: Bool = false

    var posterWidth: CGFloat = 215

    @FocusState private var isFocused: Bool
    @State private var themeCoordinator = AppThemeCoordinator.shared

    private var isTrailerExpanded: Bool {
        autoPlayTrailersOnFocus && themeCoordinator.expandedHomeCardKey == "series_\(series.id)"
    }

    var body: some View {
        NavigationLink(destination: SeriesDetailView(tmdbId: series.id)) {
            ZStack(alignment: .topTrailing) {
                if let path = overridePosterPath ?? series.posterPath ?? series.backdropPath,
                   let url = TMDBService.shared.imageURL(path: path, size: "w500") {
                    AuraCachedImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(2 / 3, contentMode: .fill)
                            .frame(width: posterWidth, height: posterWidth * 1.5)
                            .clipped()
                    } placeholder: {
                        posterPlaceholder
                    }
                } else {
                    posterPlaceholder
                }

                if isTrailerExpanded {
                    VStack {
                        HStack {
                            Label("Trailer", systemImage: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.75), in: Capsule())
                                .padding(10)
                            Spacer()
                        }
                        Spacer()
                    }
                    .transition(.opacity)
                }

                // Watched indicator badge (top-right circle checkmark)
                if isWatched && showWatchedBadge {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.black.opacity(0.65), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.45), lineWidth: 1)
                        )
                        .padding(10)
                }
            }
            .frame(width: posterWidth, height: posterWidth * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 3 : 1)
            )
            .scaleEffect(isTrailerExpanded ? 1.11 : (isFocused ? 1.07 : 1.0))
            .shadow(
                color: isFocused ? Color.white.opacity(isTrailerExpanded ? 0.28 : 0.18) : Color.black.opacity(0.45),
                radius: isFocused ? (isTrailerExpanded ? 24 : 18) : 6,
                y: isFocused ? 8 : 3
            )
            .animation(.easeOut(duration: 0.22), value: isFocused)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isTrailerExpanded)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused {
                themeCoordinator.onHomeCardFocused(
                    mediaType: "series",
                    tmdbId: series.id,
                    title: series.name,
                    overview: series.overview,
                    posterPath: overridePosterPath ?? series.posterPath,
                    backdropPath: series.backdropPath,
                    releaseYear: series.firstAirDate.map { String($0.prefix(4)) },
                    voteAverage: series.voteAverage,
                    autoPlayTrailers: autoPlayTrailersOnFocus
                )
            } else if autoPlayTrailersOnFocus {
                themeCoordinator.onHomeCardBlurred(mediaType: "series", tmdbId: series.id)
            }
        }
        .modifier(MediaPosterContextMenuModifier(
            tmdbId: series.id,
            mediaType: "series",
            title: series.name,
            posterPath: overridePosterPath ?? series.posterPath,
            backdropPath: series.backdropPath,
            initialWatched: isWatched
        ))
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.auraSurface)
            .frame(width: posterWidth, height: posterWidth * 1.5)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "tv")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.25))
                    Text(series.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }
    }
}
