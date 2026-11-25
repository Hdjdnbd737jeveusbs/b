import SwiftUI

// MARK: - Poster Card View (Clean 2:3 Portrait Card, No Caption, White Focus Border)

struct PosterCardView: View {
    let movie: TMDBMovie
    var isWatched: Bool = false
    var showWatchedBadge: Bool = true

    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationLink(destination: MovieDetailView(tmdbId: movie.id)) {
            ZStack(alignment: .topTrailing) {
                if let path = movie.posterPath,
                   let url = TMDBService.shared.imageURL(path: path, size: "w500") {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(2 / 3, contentMode: .fill)
                                .frame(width: 215, height: 322)
                                .clipped()
                        case .failure, .empty:
                            posterPlaceholder
                        @unknown default:
                            posterPlaceholder
                        }
                    }
                } else {
                    posterPlaceholder
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
            .frame(width: 215, height: 322)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 3 : 1)
            )
            .scaleEffect(isFocused ? 1.07 : 1.0)
            .shadow(
                color: isFocused ? Color.white.opacity(0.18) : Color.black.opacity(0.45),
                radius: isFocused ? 18 : 6,
                y: isFocused ? 8 : 3
            )
            .animation(.easeOut(duration: 0.18), value: isFocused)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($isFocused)
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.auraSurface)
            .frame(width: 215, height: 322)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "film")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.25))
                    Text(movie.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }
    }
}
