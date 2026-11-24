import SwiftUI

// MARK: - Spotlight Hero Carousel (Matching Reference Screenshot 1 & 3)

struct SpotlightCarouselView: View {
    let items: [TMDBMovie]
    @State private var currentIndex: Int = 0
    @FocusState private var isHeroFocused: Bool

    // Auto-advance timer (every 7 seconds)
    private let timer = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    var body: some View {
        if items.isEmpty {
            carouselPlaceholder
        } else {
            VStack(spacing: 16) {
                // Main hero container
                NavigationLink(destination: MovieDetailView(tmdbId: currentItem.id)) {
                    ZStack(alignment: .bottomLeading) {
                        // Backdrop Image
                        backdropView

                        // Ambient Gradient Overlays
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.85), location: 0.0),
                                .init(color: .black.opacity(0.50), location: 0.40),
                                .init(color: .clear, location: 0.85)
                            ],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        )

                        // Bottom gradient to blend into rows below
                        LinearGradient(
                            colors: [.black, .clear],
                            startPoint: .bottom,
                            endPoint: .center
                        )

                        // Metadata and Title Content Overlay
                        VStack(alignment: .leading, spacing: 14) {
                            // "RECENTLY ADDED" Eyebrow Label
                            Text("RECENTLY ADDED")
                                .font(.system(size: 15, weight: .bold))
                                .tracking(3)
                                .foregroundStyle(.white.opacity(0.75))

                            // Large Bold Title
                            Text(currentItem.title)
                                .font(.system(size: 58, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.8), radius: 8, y: 4)

                            // Metadata Line
                            HStack(spacing: 10) {
                                BadgeView(text: "TV-MA", style: .outlined, fontSize: 13)

                                if let date = currentItem.releaseDate, date.count >= 4 {
                                    Text(String(date.prefix(4)))
                                }

                                if let genres = currentItem.genreIds, !genres.isEmpty {
                                    Text("·")
                                    Text(TMDBGenres.movieGenreNames(for: genres).prefix(2).joined(separator: ", "))
                                }

                                if let vote = currentItem.voteAverage, vote > 0 {
                                    Text("·")
                                    HStack(spacing: 4) {
                                        Image(systemName: "star.fill")
                                            .foregroundStyle(.yellow)
                                            .font(.system(size: 14))
                                        Text(String(format: "%.1f", vote))
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                }
                            }
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 60)
                        .padding(.bottom, 45)
                    }
                    .frame(height: 540)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(isHeroFocused ? Color.white.opacity(0.6) : Color.white.opacity(0.08), lineWidth: isHeroFocused ? 2 : 1)
                    )
                    .scaleEffect(isHeroFocused ? 1.02 : 1.0)
                    .shadow(color: isHeroFocused ? Color.auraAccent.opacity(0.4) : Color.black.opacity(0.4), radius: 24, y: 10)
                    .animation(.easeInOut(duration: 0.25), value: isHeroFocused)
                }
                .buttonStyle(.plain)
                .focused($isHeroFocused)

                // Page Indicator Dots
                HStack(spacing: 8) {
                    ForEach(0..<items.count, id: \.self) { index in
                        Capsule()
                            .fill(index == currentIndex ? Color.white : Color.white.opacity(0.25))
                            .frame(width: index == currentIndex ? 24 : 8, height: 6)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: currentIndex)
                    }
                }
                .padding(.top, 4)
            }
            .onReceive(timer) { _ in
                guard !isHeroFocused else { return }
                withAnimation(.easeInOut(duration: 0.6)) {
                    currentIndex = (currentIndex + 1) % items.count
                }
            }
        }
    }

    private var currentItem: TMDBMovie {
        items[currentIndex % items.count]
    }

    @ViewBuilder
    private var backdropView: some View {
        if let path = currentItem.backdropPath ?? currentItem.posterPath,
           let url = TMDBService.shared.imageURL(path: path, size: "original") {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: 540)
                        .clipped()
                case .failure, .empty:
                    carouselPlaceholder
                @unknown default:
                    carouselPlaceholder
                }
            }
        } else {
            carouselPlaceholder
        }
    }

    private var carouselPlaceholder: some View {
        Rectangle()
            .fill(Color.auraSurface)
            .frame(height: 540)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                Image(systemName: "film")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.2))
            }
    }
}
