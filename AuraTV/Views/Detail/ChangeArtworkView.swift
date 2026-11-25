import SwiftUI
import SwiftData

// MARK: - Change Artwork View (Posters, Backdrops, Logos Picker with SwiftData Persistence)

struct ChangeArtworkView: View {
    let tmdbId: Int
    let mediaType: String // "movie" or "series"
    let title: String
    let defaultPosterPath: String?
    let defaultBackdropPath: String?
    let defaultLogoPath: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allCustomArtwork: [CustomArtwork]

    @State private var selectedTab: ArtworkTab = .posters
    @State private var posters: [TMDBImageAsset] = []
    @State private var backdrops: [TMDBImageAsset] = []
    @State private var logos: [TMDBImageAsset] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    @FocusState private var focusedTab: ArtworkTab?
    @FocusState private var focusedAssetPath: String?
    @FocusState private var focusedButton: ActionButton?

    enum ArtworkTab: String, CaseIterable, Identifiable {
        case posters = "Posters"
        case backdrops = "Backdrops"
        case logos = "Logos"
        var id: String { rawValue }
    }

    enum ActionButton: Hashable {
        case restore
        case done
    }

    private var recordKey: String {
        CustomArtwork.makeKey(tmdbId: tmdbId, mediaType: mediaType)
    }

    private var currentRecord: CustomArtwork? {
        allCustomArtwork.first(where: { $0.key == recordKey })
    }

    private var activePosterPath: String? {
        currentRecord?.customPosterPath ?? defaultPosterPath
    }

    private var activeBackdropPath: String? {
        currentRecord?.customBackdropPath ?? defaultBackdropPath
    }

    private var activeLogoPath: String? {
        currentRecord?.customLogoPath ?? defaultLogoPath
    }

    private var currentAssets: [TMDBImageAsset] {
        switch selectedTab {
        case .posters: return posters
        case .backdrops: return backdrops
        case .logos: return logos
        }
    }

    private var focusedAsset: TMDBImageAsset? {
        guard let focusedAssetPath else { return nil }
        return currentAssets.first(where: { $0.filePath == focusedAssetPath })
    }

    var body: some View {
        ZStack {
            Color.auraBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 26) {
                // Header + Artwork Category Pills
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CHANGE ARTWORK")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(2.5)
                            .foregroundStyle(.white.opacity(0.6))
                        Text(title)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    Spacer()

                    HStack(spacing: 16) {
                        ForEach(ArtworkTab.allCases) { tab in
                            let isSelected = selectedTab == tab
                            let isFocused = focusedTab == tab

                            Button {
                                selectedTab = tab
                            } label: {
                                Text(tab.rawValue)
                                    .font(.system(size: 18, weight: isSelected || isFocused ? .bold : .medium))
                                    .foregroundStyle(isSelected || isFocused ? Color.black : Color.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 11)
                                    .background((isSelected || isFocused) ? Color.white : Color.white.opacity(0.12), in: Capsule())
                                    .scaleEffect(isFocused ? 1.05 : 1.0)
                                    .animation(.easeOut(duration: 0.16), value: focusedTab)
                            }
                            .buttonStyle(AuraButtonStyle())
                            .focusEffectDisabled()
                            .focused($focusedTab, equals: tab)
                        }
                    }
                }

                // Main Split: Left Live Preview | Right Asset Grid
                HStack(alignment: .top, spacing: 40) {
                    leftPreviewColumn
                        .frame(width: 540)

                    rightAssetsGrid
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 70)
            .padding(.vertical, 48)
        }
        .task {
            await loadArtwork()
        }
        .onExitCommand {
            dismiss()
        }
    }

    // MARK: - Left Live Preview Column

    private var leftPreviewColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Live Hero + Poster Overlay Card
            ZStack(alignment: .bottomTrailing) {
                // Mini Backdrop
                ZStack(alignment: .bottomLeading) {
                    if let backdrop = activeBackdropPath,
                       let url = TMDBService.shared.imageURL(path: backdrop, size: "w780") {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(16 / 9, contentMode: .fill)
                                    .frame(width: 540, height: 304)
                                    .clipped()
                            } else {
                                Color.auraSurface.frame(width: 540, height: 304)
                            }
                        }
                    } else {
                        Color.auraSurface.frame(width: 540, height: 304)
                    }

                    LinearGradient(
                        colors: [Color.auraBackground.opacity(0.92), .clear],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        TitleLogoView(
                            title: title,
                            mediaType: mediaType,
                            tmdbId: tmdbId,
                            preloadedLogoPath: activeLogoPath,
                            maxWidth: 270,
                            maxHeight: 68,
                            fallbackFontSize: 26,
                            alignment: .leading
                        )

                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Play")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.white, in: Capsule())
                    }
                    .padding(22)
                }
                .frame(width: 540, height: 304)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )

                // Mini Poster Preview on right corner
                if let poster = activePosterPath,
                   let posterURL = TMDBService.shared.imageURL(path: poster, size: "w342") {
                    AsyncImage(url: posterURL) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(2 / 3, contentMode: .fill)
                                .frame(width: 112, height: 168)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                                )
                                .shadow(color: .black.opacity(0.7), radius: 12, y: 4)
                                .padding(14)
                        }
                    }
                }
            }

            // Focused Asset Metadata Line
            VStack(alignment: .leading, spacing: 6) {
                Text(focusedAsset != nil ? "Press Select to Apply" : "Current Artwork")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                if let asset = focusedAsset, let w = asset.width, let h = asset.height {
                    let lang = asset.iso6391?.uppercased() ?? "Textless"
                    Text("\(w) × \(h) • \(lang) • TMDB")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.auraSecondaryText)
                } else {
                    Text("\(posters.count) posters • \(backdrops.count) backdrops • \(logos.count) logos")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.auraSecondaryText)
                }
            }

            // Action Buttons: Restore Default & Done
            HStack(spacing: 14) {
                Button {
                    restoreDefaultArtwork()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Restore Default")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(focusedButton == .restore ? Color.black : Color.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(focusedButton == .restore ? Color.white : Color.white.opacity(0.14), in: Capsule())
                    .scaleEffect(focusedButton == .restore ? 1.05 : 1.0)
                    .animation(.easeOut(duration: 0.16), value: focusedButton)
                }
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()
                .focused($focusedButton, equals: .restore)

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Color.white, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(focusedButton == .done ? Color.white : .clear, lineWidth: 2.5)
                                .padding(-4)
                        )
                        .scaleEffect(focusedButton == .done ? 1.05 : 1.0)
                        .animation(.easeOut(duration: 0.16), value: focusedButton)
                }
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()
                .focused($focusedButton, equals: .done)
            }

            Spacer()
        }
    }

    // MARK: - Right Asset Grid

    @ViewBuilder
    private var rightAssetsGrid: some View {
        if isLoading {
            VStack {
                Spacer()
                ProgressView().scaleEffect(1.5).tint(.white)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let errorMessage {
            VStack(spacing: 12) {
                Spacer()
                Text("Could not load artwork")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text(errorMessage)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.auraSecondaryText)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if currentAssets.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.3))
                Text("No \(selectedTab.rawValue) Available")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            let columns = selectedTab == .posters
                ? [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 22)]
                : [GridItem(.adaptive(minimum: 360, maximum: 420), spacing: 22)]

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(currentAssets, id: \.filePath) { asset in
                        artworkCard(for: asset)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private func artworkCard(for asset: TMDBImageAsset) -> some View {
        let isFocused = focusedAssetPath == asset.filePath
        let isCurrent = isAssetActive(asset.filePath)
        let ratio: CGFloat = selectedTab == .posters ? (2 / 3) : (16 / 9)
        let sizeParam = selectedTab == .backdrops ? "w780" : "w500"

        Button {
            applyArtwork(asset.filePath)
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let url = TMDBService.shared.imageURL(path: asset.filePath, size: sizeParam) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: selectedTab == .logos ? .fit : .fill)
                                    .padding(selectedTab == .logos ? 20 : 0)
                            default:
                                Color.auraSurface
                            }
                        }
                    } else {
                        Color.auraSurface
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(ratio, contentMode: .fit)
                .background(selectedTab == .logos ? Color.auraSurface : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if isCurrent {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Current")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white, in: Capsule())
                    .padding(10)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.1), lineWidth: isFocused ? 3 : 1)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .shadow(color: isFocused ? Color.white.opacity(0.16) : .black.opacity(0.4), radius: isFocused ? 16 : 6)
            .animation(.easeOut(duration: 0.16), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedAssetPath, equals: asset.filePath)
    }

    // MARK: - Logic & Persistence

    private func isAssetActive(_ path: String) -> Bool {
        switch selectedTab {
        case .posters: return activePosterPath == path
        case .backdrops: return activeBackdropPath == path
        case .logos: return activeLogoPath == path
        }
    }

    @MainActor
    private func loadArtwork() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await TMDBService.shared.fetchAllArtwork(mediaType: mediaType, id: tmdbId)
            posters = response.posters ?? []
            backdrops = response.backdrops ?? []
            logos = (response.logos ?? []).filter { !$0.filePath.lowercased().hasSuffix(".svg") }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func applyArtwork(_ path: String) {
        let record: CustomArtwork
        if let existing = currentRecord {
            record = existing
        } else {
            record = CustomArtwork(key: recordKey, tmdbId: tmdbId, mediaType: mediaType)
            modelContext.insert(record)
        }

        switch selectedTab {
        case .posters:
            record.customPosterPath = path
        case .backdrops:
            record.customBackdropPath = path
        case .logos:
            record.customLogoPath = path
        }
        record.updatedAt = Date()
        try? modelContext.save()
    }

    @MainActor
    private func restoreDefaultArtwork() {
        if let existing = currentRecord {
            modelContext.delete(existing)
            try? modelContext.save()
        }
    }
}
