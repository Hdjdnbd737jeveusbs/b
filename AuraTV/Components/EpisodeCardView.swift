import SwiftUI

// MARK: - Episode Card View (16:9 Aspect Ratio)

struct EpisodeCardView: View {
    let episode: TMDBEpisode
    var isWatched: Bool = false
    var blurThumbnail: Bool = false
    var hideDescription: Bool = false
    var isSpoilerRevealed: Bool = false
    var onToggleWatched: (() -> Void)? = nil
    var onToggleSpoilerReveal: (() -> Void)? = nil
    var onPlay: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    init(
        episode: TMDBEpisode,
        isWatched: Bool = false,
        blurThumbnail: Bool = false,
        hideDescription: Bool = false,
        isSpoilerRevealed: Bool = false,
        onToggleWatched: (() -> Void)? = nil,
        onToggleSpoilerReveal: (() -> Void)? = nil,
        onPlay: (() -> Void)? = nil
    ) {
        self.episode = episode
        self.isWatched = isWatched
        self.blurThumbnail = blurThumbnail
        self.hideDescription = hideDescription
        self.isSpoilerRevealed = isSpoilerRevealed
        self.onToggleWatched = onToggleWatched
        self.onToggleSpoilerReveal = onToggleSpoilerReveal
        self.onPlay = onPlay
    }

    private var shouldBlurThumbnail: Bool {
        blurThumbnail && !isWatched && !isSpoilerRevealed && !isFocused
    }

    private var shouldHideDescription: Bool {
        hideDescription && !isWatched && !isSpoilerRevealed && !isFocused
    }

    var body: some View {
        Button(action: { onPlay?() }) {
            VStack(alignment: .leading, spacing: 10) {
                // Episode still image (16:9)
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let path = episode.stillPath,
                           let url = TMDBService.shared.imageURL(path: path, size: "w780") {
                            AuraCachedImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(16/9, contentMode: .fill)
                                    .frame(width: 360, height: 202)
                            } placeholder: {
                                episodePlaceholder
                            }
                        } else {
                            episodePlaceholder
                        }
                    }
                    .blur(radius: shouldBlurThumbnail ? 18 : 0)
                    .frame(width: 360, height: 202)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        if shouldBlurThumbnail {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.32))
                                .overlay {
                                    VStack(spacing: 6) {
                                        Image(systemName: "eye.slash.fill")
                                            .font(.system(size: 22, weight: .semibold))
                                        Text("Spoiler Shield")
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.black.opacity(0.55), in: Capsule())
                                }
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: shouldBlurThumbnail)

                    // Top-right watched badge & bottom-right runtime badge
                    if isWatched {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(Color.black.opacity(0.65), in: Circle())
                                    .padding(8)
                            }
                            Spacer()
                        }
                    }

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

                    if shouldHideDescription {
                        Text("Synopsis hidden · Focus or mark watched to reveal")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.45))
                            .italic()
                            .lineLimit(2)
                    } else if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.auraSecondaryText)
                            .lineLimit(2)
                            .lineSpacing(2)
                    }
                }
                .frame(width: 360, alignment: .leading)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 3 : 1)
                    .frame(width: 360, height: 202),
                alignment: .top
            )
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .shadow(
                color: isFocused ? Color.white.opacity(0.16) : Color.black.opacity(0.35),
                radius: isFocused ? 18 : 6,
                y: isFocused ? 8 : 3
            )
            .animation(.easeOut(duration: 0.18), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
        .contextMenu {
            Button("Play Episode") {
                onPlay?()
            }
            if let onToggleWatched {
                Button(isWatched ? "Mark Episode as Unwatched" : "Mark Episode as Watched") {
                    onToggleWatched()
                }
            }
            if !isWatched, (blurThumbnail || hideDescription), let onToggleSpoilerReveal {
                Button(isSpoilerRevealed ? "Hide Spoiler" : "Reveal Spoiler") {
                    onToggleSpoilerReveal()
                }
            }
        }
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
