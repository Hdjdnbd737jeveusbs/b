import SwiftUI

// MARK: - Series Card View (16:9 Backdrop Card for Series Tab)

struct SeriesCardView: View, Equatable {
    let series: TMDBSeries
    var overrideBackdropPath: String? = nil
    var isFirstInRow: Bool = false

    @FocusState private var isFocused: Bool

    static func == (lhs: SeriesCardView, rhs: SeriesCardView) -> Bool {
        lhs.series.id == rhs.series.id &&
        lhs.overrideBackdropPath == rhs.overrideBackdropPath &&
        lhs.isFirstInRow == rhs.isFirstInRow
    }

    var body: some View {
        NavigationLink(destination: SeriesDetailView(tmdbId: series.id)) {
            VStack(alignment: .leading, spacing: 8) {
                // 16:9 Backdrop with gradient and title
                ZStack(alignment: .bottomLeading) {
                    if let path = overrideBackdropPath ?? series.backdropPath ?? series.posterPath,
                       let url = TMDBService.shared.imageURL(path: path, size: "w780") {
                        AuraCachedImage(url: url, targetSize: CGSize(width: 380, height: 214)) { image in
                            image
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fill)
                                .frame(width: 380, height: 214)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        } placeholder: {
                            backdropPlaceholder
                        }
                    } else {
                        backdropPlaceholder
                    }

                    // Subtle bottom gradient
                    LinearGradient(
                        colors: [.black.opacity(0.8), .clear],
                        startPoint: .bottom,
                        endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .frame(width: 380, height: 214)

                    // Title overlay at bottom
                    VStack(alignment: .leading, spacing: 3) {
                        Text(series.name)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            if let date = series.firstAirDate, date.count >= 4 {
                                Text(String(date.prefix(4)))
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white.opacity(0.75))
                            }

                            if let vote = series.voteAverage, vote > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.yellow)
                                    Text(String(format: "%.1f", vote))
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.92))
                                }
                            }
                        }
                    }
                    .padding(14)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 3 : 1)
            )
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
        .auraLeftEdgeSidebarTrigger(isFirstInRow)
        .onChange(of: isFocused) { _, focused in
            if focused {
                AppThemeCoordinator.shared.updateFocusedArtwork(
                    posterPath: series.posterPath,
                    backdropPath: overrideBackdropPath ?? series.backdropPath
                )
            }
        }
        .modifier(MediaPosterContextMenuModifier(
            tmdbId: series.id,
            mediaType: "series",
            title: series.name,
            posterPath: series.posterPath,
            backdropPath: overrideBackdropPath ?? series.backdropPath,
            initialWatched: false
        ))
    }

    private var backdropPlaceholder: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.auraSurface)
            .frame(width: 380, height: 214)
            .overlay {
                Image(systemName: "tv")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.25))
            }
    }
}
