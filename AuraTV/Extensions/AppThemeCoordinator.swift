import Foundation
import SwiftUI
import Observation

// MARK: - Background Theme Styles (Settings > Appearance)

enum AuraBackgroundStyle: String, CaseIterable, Identifiable {
    case oledBlack = "OLED Black"
    case softGlow = "Soft Glow"
    case posterBehindPage = "Poster Behind the Page"

    var id: String { rawValue }

    init(settingValue: String) {
        switch settingValue {
        case AuraBackgroundStyle.oledBlack.rawValue:
            self = .oledBlack
        case AuraBackgroundStyle.posterBehindPage.rawValue:
            self = .posterBehindPage
        default:
            self = .softGlow
        }
    }
}

// MARK: - Focused Media Preview & Dynamic Theme Coordinator

struct HomeFocusedTrailerPreview: Equatable {
    let mediaType: String // "movie" or "series"
    let tmdbId: Int
    let title: String
    let overview: String?
    let backdropPath: String?
    let posterPath: String?
    let releaseYear: String?
    let voteAverage: Double?
    let trailerName: String?
    let trailerStreamURL: URL?
}

@Observable
@MainActor
final class AppThemeCoordinator {
    static let shared = AppThemeCoordinator()

    var focusedPosterURL: URL?
    var focusedBackdropURL: URL?
    var focusedGlowColor: Color = .clear
    var expandedHomeCardKey: String?
    var heroTrailerPreview: HomeFocusedTrailerPreview?

    private var glowTask: Task<Void, Never>?
    private var homeFocusDebounceTask: Task<Void, Never>?

    private init() {}

    func updateFocusedArtwork(posterPath: String?, backdropPath: String?) {
        let posterURL = TMDBService.shared.imageURL(path: posterPath, size: "w500")
        let backdropURL = TMDBService.shared.imageURL(path: backdropPath ?? posterPath, size: "w1280")

        if focusedPosterURL == posterURL && focusedBackdropURL == backdropURL {
            return
        }

        focusedPosterURL = posterURL
        focusedBackdropURL = backdropURL

        glowTask?.cancel()
        guard let colorSourceURL = posterURL ?? backdropURL else {
            focusedGlowColor = .clear
            return
        }

        glowTask = Task { @MainActor [weak self] in
            let color = await AuraImageCache.shared.extractGlowColor(for: colorSourceURL)
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                self.focusedGlowColor = color ?? Color.auraAccent
            }
        }
    }

    func onHomeCardFocused(
        mediaType: String,
        tmdbId: Int,
        title: String,
        overview: String?,
        posterPath: String?,
        backdropPath: String?,
        releaseYear: String?,
        voteAverage: Double?,
        autoPlayTrailers: Bool
    ) {
        updateFocusedArtwork(posterPath: posterPath, backdropPath: backdropPath)

        let cardKey = "\(mediaType)_\(tmdbId)"
        homeFocusDebounceTask?.cancel()

        guard autoPlayTrailers else {
            expandedHomeCardKey = nil
            heroTrailerPreview = nil
            return
        }

        homeFocusDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.0))
            guard let self, !Task.isCancelled else { return }

            let trailer = await TrailerPreviewService.shared.fetchTrailer(mediaType: mediaType, tmdbId: tmdbId)
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.35)) {
                self.expandedHomeCardKey = cardKey
                self.heroTrailerPreview = HomeFocusedTrailerPreview(
                    mediaType: mediaType,
                    tmdbId: tmdbId,
                    title: title,
                    overview: overview,
                    backdropPath: backdropPath,
                    posterPath: posterPath,
                    releaseYear: releaseYear,
                    voteAverage: voteAverage,
                    trailerName: trailer?.videoName,
                    trailerStreamURL: trailer?.playableStreamURL
                )
            }
        }
    }

    func onHomeCardBlurred(mediaType: String, tmdbId: Int) {
        let cardKey = "\(mediaType)_\(tmdbId)"
        homeFocusDebounceTask?.cancel()
        if expandedHomeCardKey == cardKey {
            withAnimation(.easeOut(duration: 0.25)) {
                expandedHomeCardKey = nil
                heroTrailerPreview = nil
            }
        }
    }

    func clearHomePreview() {
        homeFocusDebounceTask?.cancel()
        expandedHomeCardKey = nil
        heroTrailerPreview = nil
    }
}

// MARK: - Dynamic App Background Layer

struct AuraDynamicBackgroundView: View {
    let styleSetting: String
    var fallbackBackdropURL: URL? = nil

    @State private var coordinator = AppThemeCoordinator.shared

    private var style: AuraBackgroundStyle {
        AuraBackgroundStyle(settingValue: styleSetting)
    }

    var body: some View {
        ZStack {
            switch style {
            case .oledBlack:
                Color.black
                    .ignoresSafeArea()

            case .softGlow:
                Color.auraBackground
                    .ignoresSafeArea()

                if coordinator.focusedGlowColor != .clear {
                    RadialGradient(
                        stops: [
                            .init(color: coordinator.focusedGlowColor.opacity(0.28), location: 0.0),
                            .init(color: coordinator.focusedGlowColor.opacity(0.08), location: 0.52),
                            .init(color: .clear, location: 0.88)
                        ],
                        center: UnitPoint(x: 0.72, y: 0.22),
                        startRadius: 20,
                        endRadius: 960
                    )
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.45), value: coordinator.focusedGlowColor)
                }

            case .posterBehindPage:
                Color.auraBackground
                    .ignoresSafeArea()

                if let url = coordinator.focusedBackdropURL ?? coordinator.focusedPosterURL ?? fallbackBackdropURL {
                    AuraCachedImage(url: url, targetSize: CGSize(width: 480, height: 270)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .ignoresSafeArea()
                            .opacity(0.24)
                            .overlay(Color.auraBackground.opacity(0.72))
                    } placeholder: {
                        Color.auraBackground.ignoresSafeArea()
                    }
                }
            }
        }
    }
}
