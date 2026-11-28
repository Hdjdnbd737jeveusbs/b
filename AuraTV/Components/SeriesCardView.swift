import SwiftUI

// MARK: - Series Card View (16:9 Landscape Card with 22pt Title & 18pt Rating Underneath)

struct SeriesCardView: View, Equatable {
    let series: TMDBSeries
    var overrideBackdropPath: String? = nil
    var cardWidth: CGFloat = 400
    var isFirstInRow: Bool = false
    var memoryTabKey: String? = "Series"

    @FocusState private var isFocused: Bool
    @State private var navMemory = AuraNavigationMemory.shared

    private var cardHeight: CGFloat { (cardWidth * 9.0 / 16.0).rounded() }
    private var focusId: String { "series_\(series.id)" }

    static func == (lhs: SeriesCardView, rhs: SeriesCardView) -> Bool {
        lhs.series.id == rhs.series.id &&
        lhs.overrideBackdropPath == rhs.overrideBackdropPath &&
        lhs.cardWidth == rhs.cardWidth &&
        lhs.isFirstInRow == rhs.isFirstInRow &&
        lhs.memoryTabKey == rhs.memoryTabKey
    }

    private var subtitleLine: String {
        var parts: [String] = []
        if let date = series.firstAirDate, date.count >= 4 {
            parts.append(String(date.prefix(4)))
        }
        if let vote = series.voteAverage, vote > 0 {
            parts.append("★ \(String(format: "%.1f", vote))")
        }
        if let genre = TMDBGenres.tvGenreNames(for: series.genreIds).first {
            parts.append(genre)
        }
        return parts.isEmpty ? "TV Series" : parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationLink(destination: SeriesDetailView(tmdbId: series.id)) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    if let path = overrideBackdropPath ?? series.backdropPath ?? series.posterPath,
                       let url = TMDBService.shared.imageURL(path: path, size: "w780") {
                        AuraCachedImage(url: url, targetSize: CGSize(width: cardWidth, height: cardHeight)) { image in
                            image
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fill)
                                .frame(width: cardWidth, height: cardHeight)
                                .clipped()
                        } placeholder: {
                            backdropPlaceholder
                        }
                    } else {
                        backdropPlaceholder
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isFocused ? Color.white : Color.white.opacity(0.14), lineWidth: isFocused ? 3.5 : 1)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(series.name)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(subtitleLine)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255))
                        .lineLimit(1)
                }
                .frame(width: cardWidth, alignment: .leading)
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
                if let tabKey = memoryTabKey {
                    AuraNavigationMemory.shared.recordFocus(tab: tabKey, itemId: focusId)
                }
                AppThemeCoordinator.shared.updateFocusedArtwork(
                    posterPath: series.posterPath,
                    backdropPath: overrideBackdropPath ?? series.backdropPath
                )
            }
        }
        .onChange(of: navMemory.restoreTick(for: memoryTabKey ?? "")) { _, _ in
            if let tabKey = memoryTabKey,
               AuraNavigationMemory.shared.lastFocusedId(for: tabKey) == focusId {
                DispatchQueue.main.async {
                    isFocused = true
                }
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
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.auraCardSurface)
            .frame(width: cardWidth, height: cardHeight)
            .overlay {
                Image(systemName: "tv")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.25))
            }
    }
}
