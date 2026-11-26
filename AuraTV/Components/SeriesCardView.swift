import SwiftUI

// MARK: - Series Card View (16:9 Backdrop Card for Series Tab)

struct SeriesCardView: View {
    let series: TMDBSeries
    var overrideBackdropPath: String? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationLink(destination: SeriesDetailView(tmdbId: series.id)) {
            VStack(alignment: .leading, spacing: 8) {
                // 16:9 Backdrop with gradient and title
                ZStack(alignment: .bottomLeading) {
                    if let path = overrideBackdropPath ?? series.backdropPath ?? series.posterPath,
                       let url = TMDBService.shared.imageURL(path: path, size: "w780") {
                        AuraCachedImage(url: url) { image in
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(series.name)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            if let date = series.firstAirDate, date.count >= 4 {
                                Text(String(date.prefix(4)))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.7))
                            }

                            if let vote = series.voteAverage, vote > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.yellow)
                                    Text(String(format: "%.1f", vote))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 3 : 1)
            )
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .shadow(
                color: isFocused ? Color.white.opacity(0.16) : Color.black.opacity(0.4),
                radius: isFocused ? 18 : 6,
                y: isFocused ? 8 : 3
            )
            .animation(.easeOut(duration: 0.18), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
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
