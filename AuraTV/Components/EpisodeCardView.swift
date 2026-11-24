import SwiftUI

// MARK: - Episode Card View (16:9 Aspect Ratio)

struct EpisodeCardView: View {
    let episode: TMDBEpisode
    var onPlay: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    init(episode: TMDBEpisode, onPlay: (() -> Void)? = nil) {
        self.episode = episode
        self.onPlay = onPlay
    }

    var body: some View {
        Button(action: { onPlay?() }) {
            VStack(alignment: .leading, spacing: 10) {
                // Episode still image (16:9)
                ZStack(alignment: .bottomTrailing) {
                    if let path = episode.stillPath,
                       let url = TMDBService.shared.imageURL(path: path, size: "w780") {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(16/9, contentMode: .fill)
                                    .frame(width: 360, height: 202)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            case .failure, .empty:
                                episodePlaceholder
                            @unknown default:
                                episodePlaceholder
                            }
                        }
                    } else {
                        episodePlaceholder
                    }

                    // Runtime badge
                    if let runtime = episode.runtime, runtime > 0 {
                        Text(formatRuntime(runtime))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                            .padding(8)
                    }
                }

                // Episode Metadata
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("E\(episode.episodeNumber)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.auraAccent)

                        Text(episode.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.auraSecondaryText)
                            .lineLimit(2)
                            .lineSpacing(2)
                    }
                }
                .frame(width: 360, alignment: .leading)
            }
            .scaleEffect(isFocused ? 1.07 : 1.0)
            .shadow(
                color: isFocused ? Color.auraAccent.opacity(0.4) : Color.black.opacity(0.3),
                radius: isFocused ? 18 : 6,
                y: isFocused ? 8 : 3
            )
            .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }

    private var episodePlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.auraSurface)
            .frame(width: 360, height: 202)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("Episode \(episode.episodeNumber)")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
    }

    private func formatRuntime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }
}
