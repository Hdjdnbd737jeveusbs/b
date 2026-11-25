import SwiftUI
import Combine

// MARK: - Home Hero Mode

enum HomeHeroStyle: String {
    case ambient = "Ambient"
    case spotlight = "Spotlight"

    init(settingValue: String) {
        switch settingValue.lowercased() {
        case "spotlight": self = .spotlight
        default: self = .ambient
        }
    }
}

// MARK: - Home Hero Carousel (Ambient Edge-to-Edge & Spotlight Card Modes)

struct SpotlightCarouselView: View {
    let items: [TMDBMovie]
    var style: HomeHeroStyle = .ambient
    var logos: [Int: String] = [:]
    var runtimes: [Int: Int] = [:]
    var certifications: [Int: String] = [:]
    var showLogos: Bool = true

    @State private var currentIndex: Int = 0
    @FocusState private var isHeroFocused: Bool

    private let timer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()

    var body: some View {
        if items.isEmpty {
            heroPlaceholder
        } else {
            Group {
                switch style {
                case .ambient:
                    ambientHero
                case .spotlight:
                    spotlightHero
                }
            }
            .onReceive(timer) { _ in
                guard !isHeroFocused, items.count > 1 else { return }
                withAnimation(.easeInOut(duration: 0.55)) {
                    currentIndex = (currentIndex + 1) % items.count
                }
            }
        }
    }

    private var currentItem: TMDBMovie {
        items[currentIndex % items.count]
    }

    private var nextItem: TMDBMovie {
        items[(currentIndex + 1) % items.count]
    }

    // MARK: - Style A: Full-Bleed Ambient Hero (Default)

    private var ambientHero: some View {
        NavigationLink(destination: MovieDetailView(tmdbId: currentItem.id)) {
            ZStack(alignment: .bottomLeading) {
                // Full-bleed background artwork
                backdropImage(for: currentItem, width: nil, height: 640)
                    .frame(maxWidth: .infinity, height: 640)
                    .clipped()

                // Left-side vignette for legible white text & logo
                LinearGradient(
                    stops: [
                        .init(color: Color.auraBackground.opacity(0.95), location: 0.0),
                        .init(color: Color.auraBackground.opacity(0.75), location: 0.28),
                        .init(color: Color.auraBackground.opacity(0.32), location: 0.55),
                        .init(color: .clear, location: 0.85)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                // Smooth bottom fade into #090B10 app background
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.35),
                        .init(color: Color.auraBackground.opacity(0.72), location: 0.72),
                        .init(color: Color.auraBackground, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Bottom content row: Left metadata/logo/synopsis + Right pagination pills
                HStack(alignment: .bottom, spacing: 40) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("RECENTLY ADDED")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(2.8)
                            .foregroundStyle(.white.opacity(0.72))

                        heroTitleView(for: currentItem, maxWidth: 560, maxHeight: 130, fallbackSize: 54)

                        metadataRow(for: currentItem)

                        if let overview = currentItem.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(3)
                                .lineSpacing(3)
                                .frame(maxWidth: 660, alignment: .leading)
                        }
                    }

                    Spacer()

                    // Bottom-right pagination pills
                    paginationDots(activeWidth: 22, dotWidth: 10, height: 5)
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 34)
            }
            .frame(maxWidth: .infinity, minHeight: 640, maxHeight: 640)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if isHeroFocused {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: 4, height: 140)
                        .padding(.leading, 62)
                        .padding(.bottom, 40)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: isHeroFocused)
        }
        .buttonStyle(.plain)
        .focused($isHeroFocused)
    }

    // MARK: - Style B: Spotlight Rounded Carousel (With Peeking Next Card)

    private var spotlightHero: some View {
        VStack(spacing: 18) {
            GeometryReader { geometry in
                let cardWidth = max(geometry.size.width - 200, 960)
                let cardHeight: CGFloat = 490

                HStack(spacing: 28) {
                    // Main Active Hero Card
                    NavigationLink(destination: MovieDetailView(tmdbId: currentItem.id)) {
                        ZStack(alignment: .bottomLeading) {
                            backdropImage(for: currentItem, width: cardWidth, height: cardHeight)

                            LinearGradient(
                                stops: [
                                    .init(color: Color.auraBackground.opacity(0.92), location: 0.0),
                                    .init(color: Color.auraBackground.opacity(0.55), location: 0.42),
                                    .init(color: .clear, location: 0.88)
                                ],
                                startPoint: .bottomLeading,
                                endPoint: .topTrailing
                            )

                            LinearGradient(
                                colors: [Color.auraBackground.opacity(0.95), .clear],
                                startPoint: .bottom,
                                endPoint: .center
                            )

                            VStack(alignment: .leading, spacing: 12) {
                                Text("RECENTLY ADDED")
                                    .font(.system(size: 13, weight: .bold))
                                    .tracking(2.8)
                                    .foregroundStyle(.white.opacity(0.72))

                                heroTitleView(for: currentItem, maxWidth: 520, maxHeight: 120, fallbackSize: 52)

                                metadataRow(for: currentItem)

                                if let overview = currentItem.overview, !overview.isEmpty {
                                    Text(overview)
                                        .font(.system(size: 17))
                                        .foregroundStyle(.white.opacity(0.75))
                                        .lineLimit(2)
                                        .frame(maxWidth: 620, alignment: .leading)
                                }
                            }
                            .padding(.horizontal, 52)
                            .padding(.bottom, 38)
                        }
                        .frame(width: cardWidth, height: cardHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(isHeroFocused ? Color.white : Color.white.opacity(0.12), lineWidth: isHeroFocused ? 3 : 1)
                        )
                        .scaleEffect(isHeroFocused ? 1.015 : 1.0)
                        .shadow(
                            color: isHeroFocused ? Color.white.opacity(0.15) : Color.black.opacity(0.5),
                            radius: 22,
                            y: 10
                        )
                        .animation(.easeOut(duration: 0.2), value: isHeroFocused)
                    }
                    .buttonStyle(.plain)
                    .focused($isHeroFocused)

                    // Next Peeking Card on the right edge
                    if items.count > 1 {
                        ZStack(alignment: .bottomLeading) {
                            backdropImage(for: nextItem, width: cardWidth, height: cardHeight)

                            LinearGradient(
                                colors: [Color.auraBackground.opacity(0.85), .clear],
                                startPoint: .bottom,
                                endPoint: .top
                            )

                            VStack(alignment: .leading, spacing: 8) {
                                Text("RECENTLY ADDED")
                                    .font(.system(size: 12, weight: .bold))
                                    .tracking(2.5)
                                    .foregroundStyle(.white.opacity(0.65))

                                heroTitleView(for: nextItem, maxWidth: 360, maxHeight: 80, fallbackSize: 36)
                            }
                            .padding(.leading, 36)
                            .padding(.bottom, 36)
                        }
                        .frame(width: cardWidth, height: cardHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .opacity(0.78)
                    }
                }
                .padding(.leading, 80)
            }
            .frame(height: 500)

            // Centered pagination dots underneath Spotlight card
            paginationDots(activeWidth: 22, dotWidth: 8, height: 5)
        }
        .padding(.top, 92)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func heroTitleView(for item: TMDBMovie, maxWidth: CGFloat, maxHeight: CGFloat, fallbackSize: CGFloat) -> some View {
        TitleLogoView(
            title: item.title,
            mediaType: "movie",
            tmdbId: item.id,
            preloadedLogoPath: showLogos ? logos[item.id] : nil,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            fallbackFontSize: fallbackSize,
            alignment: .leading
        )
    }

    @ViewBuilder
    private func metadataRow(for item: TMDBMovie) -> some View {
        HStack(spacing: 10) {
            let cert = certifications[item.id] ?? (item.adult == true ? "R" : "PG-13")
            BadgeView(text: cert, style: .outlined, fontSize: 12)

            if let date = item.releaseDate, date.count >= 4 {
                Text("•")
                    .foregroundStyle(.white.opacity(0.5))
                Text(String(date.prefix(4)))
            }

            if let runtime = runtimes[item.id], runtime > 0 {
                Text("•")
                    .foregroundStyle(.white.opacity(0.5))
                Text(formatRuntime(runtime))
            }

            if let genres = item.genreIds, !genres.isEmpty {
                Text("•")
                    .foregroundStyle(.white.opacity(0.5))
                Text(TMDBGenres.movieGenreNames(for: genres).prefix(2).joined(separator: ", "))
                    .lineLimit(1)
            }

            if let vote = item.voteAverage, vote > 0 {
                Text("•")
                    .foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 14))
                    Text(String(format: "%.1f", vote))
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(.white.opacity(0.88))
    }

    @ViewBuilder
    private func backdropImage(for item: TMDBMovie, width: CGFloat?, height: CGFloat) -> some View {
        if let path = item.backdropPath ?? item.posterPath,
           let url = TMDBService.shared.imageURL(path: path, size: "w1280") {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: width ?? .infinity, minHeight: height, maxHeight: height)
                        .clipped()
                case .failure, .empty:
                    backdropPlaceholder(width: width, height: height)
                @unknown default:
                    backdropPlaceholder(width: width, height: height)
                }
            }
        } else {
            backdropPlaceholder(width: width, height: height)
        }
    }

    @ViewBuilder
    private func backdropPlaceholder(width: CGFloat?, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.auraSurface)
            .frame(maxWidth: width ?? .infinity, minHeight: height, maxHeight: height)
            .overlay {
                Image(systemName: "film")
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.18))
            }
    }

    private func paginationDots(activeWidth: CGFloat, dotWidth: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 7) {
            ForEach(0..<items.count, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.28))
                    .frame(width: index == currentIndex ? activeWidth : dotWidth, height: height)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentIndex)
            }
        }
    }

    private var heroPlaceholder: some View {
        Rectangle()
            .fill(Color.auraSurface)
            .frame(maxWidth: .infinity, height: style == .ambient ? 640 : 500)
            .overlay {
                ProgressView()
                    .tint(.white.opacity(0.5))
            }
    }

    private func formatRuntime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        }
        return "\(mins)m"
    }
}
