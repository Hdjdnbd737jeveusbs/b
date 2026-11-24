import SwiftUI

// MARK: - Loading Overlay View

/// Cinematic loading overlay shown while the player is buffering.
/// Displays the full-screen blurred backdrop image with the title and a progress spinner.

struct LoadingOverlayView: View {
    let title: String
    let backdropPath: String?

    var body: some View {
        ZStack {
            // Full-screen backdrop
            backdropLayer

            // Dark gradient overlay
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .black.opacity(0.3), location: 0.0),
                    .init(color: .black.opacity(0.6), location: 0.5),
                    .init(color: .black.opacity(0.9), location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Content
            VStack {
                Spacer()

                // Loading spinner
                ProgressView()
                    .scaleEffect(2.0)
                    .tint(.white)
                    .padding(.bottom, 40)

                // Title
                Text(title.uppercased())
                    .font(.system(size: 42, weight: .bold))
                    .tracking(8)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 12, x: 0, y: 4)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 80)

                // "Loading..." text
                Text("Loading stream...")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 12)

                Spacer()
                    .frame(height: 120)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Backdrop Layer

    @ViewBuilder
    private var backdropLayer: some View {
        if let path = backdropPath,
           let url = TMDBService.shared.imageURL(path: path, size: "original") {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 20)
                        .scaleEffect(1.1)
                        .ignoresSafeArea()
                case .failure, .empty:
                    Color.black.ignoresSafeArea()
                @unknown default:
                    Color.black.ignoresSafeArea()
                }
            }
        } else {
            Color.black.ignoresSafeArea()
        }
    }
}
