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
    var customBackdrops: [Int: String] = [:]
    var showLogos: Bool = true
    var autoPlayTrailersOnFocus: Bool = false

    @State private var currentIndex: Int = 0
    @State private var previewStore = HeroTrailerPreviewStore.shared
    @State private var navMemory = AuraNavigationMemory.shared
    @FocusState private var isHeroFocused: Bool

    private var trailerPreview: HomeFocusedTrailerPreview? {
        autoPlayTrailersOnFocus ? previewStore.heroTrailerPreview : nil
    }

    private let timer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()

    var body: some View {
        if items.isEmpty && trailerPreview == nil {
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
                guard !isHeroFocused, trailerPreview == nil, items.count > 1 else { return }
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
        NavigationLink(destination: activeHeroDestination) {
            ZStack(alignment: .bottomLeading) {
                // Full-bleed edge-to-edge hero backdrop fading seamlessly into #000000 black
                heroBackdropLayer(width: nil, height: 590)
                    .frame(maxWidth: .infinity, minHeight: 590, maxHeight: 590)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            stops: [
                                .init(color: Color.black.opacity(0.82), location: 0.0),
                                .init(color: Color.black.opacity(0.35), location: 0.48),
                                .init(color: Color.black.opacity(0.0), location: 0.85)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.45),
                                .init(color: Color.black.opacity(0.55), location: 0.78),
                                .init(color: Color.black, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Hero Metadata Block (leading: 80pt) + Right-aligned 6 pill dashes
                HStack(alignment: .bottom, spacing: 40) {
                    VStack(alignment: .leading, spacing: 14) {
                        activeEyebrowView

                        activeTitleView(maxWidth: 520, maxHeight: 115, fallbackSize: 52)

                        activeMetadataRow

                        if let overview = activeOverview, !overview.isEmpty {
                            Text(overview)
                                .font(.system(size: 22, weight: .regular))
                                .foregroundStyle(Color(red: 199 / 255, green: 199 / 255, blue: 204 / 255))
                                .lineLimit(3)
                                .lineSpacing(4)
                                .frame(maxWidth: 680, alignment: .leading)
                        }
                    }

                    Spacer()

                    if trailerPreview == nil {
                        // 6 thin horizontal pill dashes (28x3pt) aligned bottom-right
                        paginationDots(activeWidth: 28, dotWidth: 28, height: 3, maxDots: 6)
                            .padding(.bottom, 6)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 26)
            }
            .frame(maxWidth: .infinity, minHeight: 590, maxHeight: 590)
            .clipped()
            .scaleEffect(isHeroFocused ? 1.006 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isHeroFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isHeroFocused)
        .auraLeftEdgeSidebarTrigger()
        .onChange(of: isHeroFocused) { _, focused in
            if focused {
                AuraNavigationMemory.shared.recordFocus(tab: "Home", itemId: "home_hero", scrollId: "home_top_anchor")
                AuraNavigationMemory.shared.setHomeScrolledPastHero(false)
            }
        }
        .onChange(of: navMemory.restoreTick(for: "Home")) { _, _ in
            if AuraNavigationMemory.shared.lastFocusedId(for: "Home") == "home_hero" {
                DispatchQueue.main.async {
                    isHeroFocused = true
                }
            }
        }
        .onChange(of: navMemory.homeScrollToTopTick) { _, _ in
            AuraNavigationMemory.shared.recordFocus(tab: "Home", itemId: "home_hero", scrollId: "home_top_anchor")
            AuraNavigationMemory.shared.setHomeScrolledPastHero(false)
            DispatchQueue.main.async {
                isHeroFocused = true
            }
        }
        .modifier(MediaPosterContextMenuModifier(
            tmdbId: trailerPreview?.tmdbId ?? currentItem.id,
            mediaType: trailerPreview?.mediaType ?? "movie",
            title: trailerPreview?.title ?? currentItem.title,
            posterPath: trailerPreview?.posterPath ?? currentItem.posterPath,
            backdropPath: trailerPreview?.backdropPath ?? currentItem.backdropPath
        ))
    }

    // MARK: - Style B: Spotlight Rounded Carousel (With Peeking Next Card)

    private var spotlightHero: some View {
        VStack(spacing: 18) {
            GeometryReader { geometry in
                let cardWidth = max(geometry.size.width - 200, 960)
                let cardHeight: CGFloat = 490

                HStack(spacing: 28) {
                    // Main Active Hero Card
                    NavigationLink(destination: activeHeroDestination) {
                        ZStack(alignment: .bottomLeading) {
                            heroBackdropLayer(width: cardWidth, height: cardHeight)

                            LinearGradient(
                                stops: [
                                    .init(color: Color.black.opacity(0.88), location: 0.0),
                                    .init(color: Color.black.opacity(0.52), location: 0.42),
                                    .init(color: .clear, location: 0.88)
                                ],
                                startPoint: .bottomLeading,
                                endPoint: .topTrailing
                            )

                            LinearGradient(
                                colors: [Color.black.opacity(0.92), .clear],
                                startPoint: .bottom,
                                endPoint: .center
                            )

                            VStack(alignment: .leading, spacing: 12) {
                                activeEyebrowView

                                activeTitleView(maxWidth: 520, maxHeight: 120, fallbackSize: 52)

                                activeMetadataRow

                                if let overview = activeOverview, !overview.isEmpty {
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
                                .stroke(isHeroFocused ? Color.white : Color.white.opacity(0.14), lineWidth: isHeroFocused ? 3.5 : 1)
                        )
                        .scaleEffect(isHeroFocused ? 1.015 : 1.0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isHeroFocused)
                    }
                    .buttonStyle(AuraButtonStyle())
                    .focusEffectDisabled()
                    .focused($isHeroFocused)
                    .auraLeftEdgeSidebarTrigger()
                    .onChange(of: isHeroFocused) { _, focused in
                        if focused {
                            AuraNavigationMemory.shared.recordFocus(tab: "Home", itemId: "home_hero", scrollId: "home_top_anchor")
                            AuraNavigationMemory.shared.setHomeScrolledPastHero(false)
                        }
                    }
                    .onChange(of: navMemory.restoreTick(for: "Home")) { _, _ in
                        if AuraNavigationMemory.shared.lastFocusedId(for: "Home") == "home_hero" {
                            DispatchQueue.main.async {
                                isHeroFocused = true
                            }
                        }
                    }
                    .onChange(of: navMemory.homeScrollToTopTick) { _, _ in
                        AuraNavigationMemory.shared.recordFocus(tab: "Home", itemId: "home_hero", scrollId: "home_top_anchor")
                        AuraNavigationMemory.shared.setHomeScrolledPastHero(false)
                        DispatchQueue.main.async {
                            isHeroFocused = true
                        }
                    }
                    .modifier(MediaPosterContextMenuModifier(
                        tmdbId: trailerPreview?.tmdbId ?? currentItem.id,
                        mediaType: trailerPreview?.mediaType ?? "movie",
                        title: trailerPreview?.title ?? currentItem.title,
                        posterPath: trailerPreview?.posterPath ?? currentItem.posterPath,
                        backdropPath: trailerPreview?.backdropPath ?? currentItem.backdropPath
                    ))

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
    private var activeHeroDestination: some View {
        if let preview = trailerPreview {
            if preview.mediaType == "series" {
                SeriesDetailView(tmdbId: preview.tmdbId)
            } else {
                MovieDetailView(tmdbId: preview.tmdbId)
            }
        } else {
            MovieDetailView(tmdbId: currentItem.id)
        }
    }

    private var activeOverview: String? {
        trailerPreview?.overview ?? (items.isEmpty ? nil : currentItem.overview)
    }

    @ViewBuilder
    private var activeEyebrowView: some View {
        if let preview = trailerPreview {
            HStack(spacing: 8) {
                Image(systemName: preview.trailerStreamURL != nil ? "speaker.slash.fill" : "play.tv.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(preview.trailerName.map { "TRAILER PREVIEW · \($0.uppercased())" } ?? "TRAILER PREVIEW")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(2.4)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.auraAccent)
        } else {
            Text("RECENTLY ADDED")
                .font(.system(size: 16, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(Color(red: 229 / 255, green: 229 / 255, blue: 234 / 255))
        }
    }

    @ViewBuilder
    private func activeTitleView(maxWidth: CGFloat, maxHeight: CGFloat, fallbackSize: CGFloat) -> some View {
        if let preview = trailerPreview {
            TitleLogoView(
                title: preview.title,
                mediaType: preview.mediaType == "series" ? "tv" : "movie",
                tmdbId: preview.tmdbId,
                preloadedLogoPath: showLogos && preview.mediaType == "movie" ? logos[preview.tmdbId] : nil,
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                fallbackFontSize: fallbackSize,
                alignment: .leading
            )
        } else {
            heroTitleView(for: currentItem, maxWidth: maxWidth, maxHeight: maxHeight, fallbackSize: fallbackSize)
        }
    }

    @ViewBuilder
    private var activeMetadataRow: some View {
        if let preview = trailerPreview {
            HStack(spacing: 10) {
                BadgeView(text: preview.mediaType == "series" ? "SERIES" : "MOVIE", style: .outlined, fontSize: 12)

                if let year = preview.releaseYear, !year.isEmpty {
                    Text("•")
                        .foregroundStyle(.white.opacity(0.5))
                    Text(year)
                }

                if let vote = preview.voteAverage, vote > 0 {
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
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.white.opacity(0.88))
        } else {
            metadataRow(for: currentItem)
        }
    }

    @ViewBuilder
    private func heroBackdropLayer(width: CGFloat?, height: CGFloat) -> some View {
        if let preview = trailerPreview {
            ZStack {
                backdropPathImage(path: preview.backdropPath ?? preview.posterPath, width: width, height: height)

                if let streamURL = preview.trailerStreamURL {
                    AuraMutedTrailerVideoView(url: streamURL)
                        .frame(maxWidth: width ?? .infinity, minHeight: height, maxHeight: height)
                        .clipped()
                        .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                }
            }
        } else {
            backdropImage(for: currentItem, width: width, height: height)
        }
    }

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
        let cert = certifications[item.id] ?? (item.adult == true ? "R" : "PG-13")
        let year = item.releaseDate.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil }
        let runtime = runtimes[item.id].flatMap { $0 > 0 ? formatRuntime($0) : nil }
        let genres = item.genreIds.flatMap {
            let names = TMDBGenres.movieGenreNames(for: $0).prefix(2).joined(separator: ", ")
            return names.isEmpty ? nil : names
        }
        let metaText = [year, runtime, genres].compactMap { $0 }.joined(separator: " · ")

        HStack(spacing: 10) {
            Text(cert)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255), in: RoundedRectangle(cornerRadius: 4))

            if !metaText.isEmpty {
                Text(metaText)
            }

            if let vote = item.voteAverage, vote > 0 {
                if !metaText.isEmpty {
                    Text("·")
                }
                HStack(spacing: 5) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 15))
                    Text(String(format: "%.1f", vote))
                }
            }
        }
        .font(.system(size: 21, weight: .medium))
        .foregroundStyle(Color(red: 209 / 255, green: 209 / 255, blue: 214 / 255))
    }

    @ViewBuilder
    private func backdropImage(for item: TMDBMovie, width: CGFloat?, height: CGFloat) -> some View {
        backdropPathImage(path: customBackdrops[item.id] ?? item.backdropPath ?? item.posterPath, width: width, height: height)
    }

    @ViewBuilder
    private func backdropPathImage(path: String?, width: CGFloat?, height: CGFloat) -> some View {
        if let path,
           let url = TMDBService.shared.imageURL(path: path, size: "w1280") {
            AuraCachedImage(url: url, targetSize: CGSize(width: width ?? 1920, height: height)) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: width ?? .infinity, minHeight: height, maxHeight: height)
                    .clipped()
            } placeholder: {
                backdropPlaceholder(width: width, height: height)
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

    private func paginationDots(activeWidth: CGFloat, dotWidth: CGFloat, height: CGFloat, maxDots: Int = 6) -> some View {
        let count = min(max(items.count, 1), maxDots)
        let activeIdx = currentIndex % count
        return HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == activeIdx ? Color.white : Color.white.opacity(0.30))
                    .frame(width: index == activeIdx ? activeWidth : dotWidth, height: height)
            }
        }
    }

    private var heroPlaceholder: some View {
        Rectangle()
            .fill(Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: style == .ambient ? 590 : 500)
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
