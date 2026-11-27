import SwiftUI

// MARK: - Series Poster Card View (Clean 2:3 Portrait Card for Home Row)

struct SeriesPosterCardView: View, Equatable {
    let series: TMDBSeries
    var overridePosterPath: String? = nil
    var isWatched: Bool = false
    var showWatchedBadge: Bool = true
    var autoPlayTrailersOnFocus: Bool = false
    var isFirstInRow: Bool = false

    @FocusState private var isFocused: Bool
    @State private var isTrailerExpanded: Bool = false

    static func == (lhs: SeriesPosterCardView, rhs: SeriesPosterCardView) -> Bool {
        lhs.series.id == rhs.series.id &&
        lhs.overridePosterPath == rhs.overridePosterPath &&
        lhs.isWatched == rhs.isWatched &&
        lhs.showWatchedBadge == rhs.showWatchedBadge &&
        lhs.autoPlayTrailersOnFocus == rhs.autoPlayTrailersOnFocus &&
        lhs.isFirstInRow == rhs.isFirstInRow
    }

    var body: some View {
        NavigationLink(destination: SeriesDetailView(tmdbId: series.id)) {
            ZStack(alignment: .topTrailing) {
                if let path = overridePosterPath ?? series.posterPath ?? series.backdropPath,
                   let url = TMDBService.shared.imageURL(path: path, size: "w500") {
                    AuraCachedImage(url: url, targetSize: CGSize(width: 268, height: 402)) { image in
                        image
                            .resizable()
                            .aspectRatio(2 / 3, contentMode: .fill)
                            .frame(width: 268, height: 402)
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
            .frame(width: 268, height: 402)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isFocused ? Color.white : Color.clear, lineWidth: isFocused ? 4 : 0)
            )
            .scaleEffect(isTrailerExpanded ? 1.09 : (isFocused ? 1.055 : 1.0))
            .animation(.easeOut(duration: 0.14), value: isFocused)
            .animation(.easeOut(duration: 0.25), value: isTrailerExpanded)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
        .auraLeftEdgeSidebarTrigger(isFirstInRow)
        .task(id: isFocused) {
            guard isFocused else {
                isTrailerExpanded = false
                return
            }
            AppThemeCoordinator.shared.onHomeCardFocused(
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
            if autoPlayTrailersOnFocus {
                try? await Task.sleep(for: .seconds(2.0))
                if !Task.isCancelled && isFocused {
                    isTrailerExpanded = true
                }
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused && autoPlayTrailersOnFocus {
                isTrailerExpanded = false
                AppThemeCoordinator.shared.onHomeCardBlurred(mediaType: "series", tmdbId: series.id)
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
            .frame(width: 268, height: 402)
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
