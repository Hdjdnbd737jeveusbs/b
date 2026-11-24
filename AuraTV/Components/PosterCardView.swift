import SwiftUI

// MARK: - Poster Card View (2:3 Aspect Ratio)

struct PosterCardView: View {
    let movie: TMDBMovie

    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationLink(destination: MovieDetailView(tmdbId: movie.id)) {
            VStack(alignment: .leading, spacing: 10) {
                // Poster Image
                ZStack(alignment: .topTrailing) {
                    if let path = movie.posterPath,
                       let url = TMDBService.shared.imageURL(path: path, size: "w500") {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(2/3, contentMode: .fill)
                                    .frame(width: 220, height: 330)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            case .failure, .empty:
                                posterPlaceholder
                            @unknown default:
                                posterPlaceholder
                            }
                        }
                    } else {
                        posterPlaceholder
                    }

                    // Rating badge overlay
                    if let vote = movie.voteAverage, vote > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", vote))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding(8)
                    }
                }

                // Title and year
                VStack(alignment: .leading, spacing: 3) {
                    Text(movie.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let date = movie.releaseDate, date.count >= 4 {
                        Text(String(date.prefix(4)))
                            .font(.system(size: 14))
                            .foregroundStyle(Color.auraSecondaryText)
                    }
                }
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

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.auraSurface)
            .frame(width: 220, height: 330)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "film")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.25))
                    Text(movie.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }
            }
    }
}
