import SwiftUI

// MARK: - Loading Overlay View (Full-Bleed Backdrop + Centered Title Logo)

/// Cinematic loading screen shown while the player is buffering.
/// Full-bleed crisp backdrop (darkened) with centered white title logo and subtle spinner.
struct LoadingOverlayView: View {
    let title: String
    let backdropPath: String?
    var tmdbId: Int = 0
    var mediaType: String = "movie"
    var logoPath: String? = nil

    var body: some View {
        ZStack {
            // Full-bleed crisp backdrop
            backdropLayer

            // Left & overall dark cinema gradient vignette so centered logo pops cleanly
            LinearGradient(
                stops: [
                    .init(color: Color.auraBackground.opacity(0.75), location: 0.0),
                    .init(color: Color.auraBackground.opacity(0.45), location: 0.45),
                    .init(color: Color.auraBackground.opacity(0.25), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()

            // Centered white title logo with subtle loading spinner underneath
            ZStack {
                if tmdbId > 0 {
                    TitleLogoView(
                        title: title,
                        mediaType: mediaType,
                        tmdbId: tmdbId,
                        preloadedLogoPath: logoPath,
                        maxWidth: 460,
                        maxHeight: 110,
                        fallbackFontSize: 44,
                        alignment: .center
                    )
                } else {
                    Text(title.uppercased())
                        .font(.system(size: 44, weight: .bold))
                        .tracking(8)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.85), radius: 14, x: 0, y: 4)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 80)
                }

                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.3)
                        .tint(.white.opacity(0.75))
                    Spacer()
                        .frame(height: 220)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Backdrop Layer

    @ViewBuilder
    private var backdropLayer: some View {
        if let path = backdropPath,
           let url = TMDBService.shared.imageURL(path: path, size: "original") {
            AuraCachedImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            } placeholder: {
                Color.black.ignoresSafeArea()
            }
        } else {
            Color.black.ignoresSafeArea()
        }
    }
}
