import SwiftUI

// MARK: - Title Logo View (Official TMDB Transparent Logo + Stylized Fallback)

struct TitleLogoView: View {
    let title: String
    let mediaType: String
    let tmdbId: Int
    var preloadedLogoPath: String? = nil
    var maxWidth: CGFloat = 540
    var maxHeight: CGFloat = 135
    var fallbackFontSize: CGFloat = 52
    var alignment: Alignment = .leading

    @State private var fetchedPath: String?
    @State private var activeTask: Task<Void, Never>?

    private var effectivePath: String? {
        preloadedLogoPath ?? fetchedPath
    }

    var body: some View {
        Group {
            if let path = effectivePath,
               let url = TMDBService.shared.imageURL(path: path, size: "w500") {
                AuraCachedImage(url: url, targetSize: CGSize(width: maxWidth, height: maxHeight), cropToFill: false) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: alignment)
                } placeholder: {
                    fallbackTitleView
                        .opacity(0.85)
                }
            } else {
                fallbackTitleView
            }
        }
        .onAppear {
            loadLogoIfNeeded()
        }
        .onChange(of: tmdbId) { _, _ in
            fetchedPath = nil
            loadLogoIfNeeded()
        }
    }

    private var fallbackTitleView: some View {
        Text(title.uppercased())
            .font(.system(size: fallbackFontSize, weight: .black))
            .tracking(3.5)
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.65)
            .multilineTextAlignment(alignment == .center ? .center : .leading)
            .frame(maxWidth: maxWidth, alignment: alignment)
            .shadow(color: .black.opacity(0.85), radius: 10, x: 0, y: 4)
    }

    private func loadLogoIfNeeded() {
        guard preloadedLogoPath == nil, fetchedPath == nil else { return }
        activeTask?.cancel()
        let id = tmdbId
        let type = mediaType
        activeTask = Task { @MainActor in
            let path = await TMDBService.shared.fetchBestLogoPath(mediaType: type, id: id)
            if !Task.isCancelled {
                fetchedPath = path
            }
        }
    }
}
