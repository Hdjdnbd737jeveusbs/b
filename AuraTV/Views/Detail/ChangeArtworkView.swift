import SwiftUI
import SwiftData

// MARK: - Change Artwork View (Full-Width 7-Column Grid + Toolbar + Floating Live Mini-Preview)

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
    @State private var selectedSource: ArtworkSource = .tmdb
    @State private var isMultipleArtworkEnabled: Bool = false
    @State private var selectedMultiPosters: Set<String> = []
    @State private var selectedMultiBackdrops: Set<String> = []

    @State private var posters: [TMDBImageAsset] = []
    @State private var seasonPosters: [TMDBImageAsset] = []
    @State private var backdrops: [TMDBImageAsset] = []
    @State private var logos: [TMDBImageAsset] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    @State private var showFromLinkAlert: Bool = false
    @State private var customLinkInput: String = ""

    @FocusState private var focusedToolbarItem: ToolbarControl?
    @FocusState private var focusedAssetPath: String?

    enum ArtworkTab: String, CaseIterable, Identifiable {
        case posters = "Posters"
        case seasonPosters = "Season Posters"
        case backdrops = "Backdrops"
        case logos = "Logos"
        var id: String { rawValue }
    }

    enum ArtworkSource: String, CaseIterable, Identifiable {
        case tmdb = "TMDB"
        case mediux = "MediUX"
        var id: String { rawValue }
    }

    enum ToolbarControl: Hashable {
        case tab(ArtworkTab)
        case source(ArtworkSource)
        case fromLink
        case addLogo
        case restoreDefault
        case multipleArtwork
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
        case .seasonPosters: return seasonPosters
        case .backdrops: return backdrops
        case .logos: return logos
        }
    }

    private var focusedAsset: TMDBImageAsset? {
        guard let focusedAssetPath else { return nil }
        return currentAssets.first(where: { $0.filePath == focusedAssetPath })
    }

    private var previewPosterPath: String? {
        if (selectedTab == .posters || selectedTab == .seasonPosters), let focusedAsset {
            return focusedAsset.filePath
        }
        return activePosterPath
    }

    private var previewBackdropPath: String? {
        if selectedTab == .backdrops, let focusedAsset {
            return focusedAsset.filePath
        }
        return activeBackdropPath
    }

    private var previewLogoPath: String? {
        if selectedTab == .logos, let focusedAsset {
            return focusedAsset.filePath
        }
        return activeLogoPath
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.auraBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                // Top Header Bar: Palette + "Change Artwork" + Media Title
                headerBar

                // Filter / Source / Action Toolbar Row
                toolbarRow

                // Sub-row: Multiple Artwork toggle & description
                multipleArtworkRow

                // Full-width Multi-Column Asset Grid
                assetsGrid
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 60)
            .padding(.top, 38)

            // Floating Bottom-Right Live Mini-Preview Card
            floatingMiniPreviewCard
                .padding(.trailing, 54)
                .padding(.bottom, 34)
        }
        .task {
            await loadArtwork()
        }
        .onExitCommand {
            dismiss()
        }
        .alert("Custom Artwork URL", isPresented: $showFromLinkAlert) {
            TextField("https://image.tmdb.org/t/p/original/...", text: $customLinkInput)
            Button("Apply") {
                let trimmed = customLinkInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    applyArtwork(trimmed)
                }
                customLinkInput = ""
            }
            Button("Cancel", role: .cancel) {
                customLinkInput = ""
            }
        } message: {
            Text("Paste an image URL for the active artwork category (\(selectedTab.rawValue)).")
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 16, weight: .semibold))
                Text("Change Artwork")
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.62))

            Text(title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()
        }
    }

    // MARK: - Toolbar Row

    private var toolbarRow: some View {
        HStack(spacing: 12) {
            // Left Filter Group: Posters | Season Posters | Backdrops | Logos
            HStack(spacing: 6) {
                ForEach(ArtworkTab.allCases) { tab in
                    toolbarTabButton(tab: tab)
                }
            }

            // Middle Source Group: TMDB | MediUX
            HStack(spacing: 4) {
                sourcePill(source: .tmdb, icon: "square.3.layers.3d")
                sourcePill(source: .mediux, icon: "pencil.and.outline")
            }
            .padding(4)
            .background(Color.white.opacity(0.08), in: Capsule())

            Spacer()

            // Right Action Group: From Link | Aa Add Logo | Restore Default
            HStack(spacing: 10) {
                actionToolbarButton(title: "From Link", icon: "link", control: .fromLink) {
                    showFromLinkAlert = true
                }

                actionToolbarButton(title: "Aa Add Logo", icon: nil, control: .addLogo) {
                    selectedTab = .logos
                }

                actionToolbarButton(title: "Restore Default", icon: "arrow.counterclockwise", control: .restoreDefault) {
                    restoreDefaultArtwork()
                }
            }
        }
    }

    @ViewBuilder
    private func toolbarTabButton(tab: ArtworkTab) -> some View {
        let isSelected = selectedTab == tab
        let isFocused = focusedToolbarItem == .tab(tab)

        Button {
            selectedTab = tab
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 15, weight: isSelected || isFocused ? .bold : .medium))
                .foregroundStyle(isFocused ? Color.black : (isSelected ? Color.white : Color.white.opacity(0.7)))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(isFocused ? Color.white : (isSelected ? Color.white.opacity(0.22) : Color.clear))
                )
                .scaleEffect(isFocused ? 1.04 : 1.0)
                .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedToolbarItem, equals: .tab(tab))
    }

    @ViewBuilder
    private func sourcePill(source: ArtworkSource, icon: String) -> some View {
        let isSelected = selectedSource == source
        let isFocused = focusedToolbarItem == .source(source)

        Button {
            selectedSource = source
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(source.rawValue)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(isFocused ? Color.black : (isSelected ? Color.white : Color.white.opacity(0.6)))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isFocused ? Color.white : (isSelected ? Color.white.opacity(0.16) : Color.clear))
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedToolbarItem, equals: .source(source))
    }

    @ViewBuilder
    private func actionToolbarButton(
        title: String,
        icon: String?,
        control: ToolbarControl,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focusedToolbarItem == control

        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(isFocused ? Color.black : Color.white.opacity(0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isFocused ? Color.white : Color.clear)
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedToolbarItem, equals: control)
    }

    // MARK: - Sub-Row (Multiple Artwork)

    private var multipleArtworkRow: some View {
        let isFocused = focusedToolbarItem == .multipleArtwork

        return HStack(spacing: 14) {
            Button {
                isMultipleArtworkEnabled.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "square.stack")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Multiple Artwork")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(isFocused ? Color.black : (isMultipleArtworkEnabled ? Color.white : Color.white.opacity(0.75)))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isFocused ? Color.white : (isMultipleArtworkEnabled ? Color.white.opacity(0.24) : Color.clear))
                )
                .scaleEffect(isFocused ? 1.03 : 1.0)
                .animation(.easeOut(duration: 0.14), value: isFocused)
            }
            .buttonStyle(AuraButtonStyle())
            .focusEffectDisabled()
            .focused($focusedToolbarItem, equals: .multipleArtwork)

            if isMultipleArtworkEnabled {
                Text("Posters: \(selectedMultiPosters.count) · Backdrops: \(selectedMultiBackdrops.count) · Every 5 Minutes")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                Text("Show several posters and backdrops in turn")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()
        }
    }

    // MARK: - Full-Width Assets Grid (7 Columns for Posters)

    @ViewBuilder
    private var assetsGrid: some View {
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
                    .font(.system(size: 46))
                    .foregroundStyle(.white.opacity(0.28))
                Text(selectedSource == .mediux ? "Connect MediUX set or switch to TMDB" : "No \(selectedTab.rawValue) Available")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            let isPortrait = selectedTab == .posters || selectedTab == .seasonPosters
            let columns = isPortrait
                ? Array(repeating: GridItem(.flexible(), spacing: 14), count: 7)
                : Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(currentAssets, id: \.filePath) { asset in
                        artworkCard(for: asset, isPortrait: isPortrait)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 8)
                .padding(.bottom, 220)
            }
        }
    }

    @ViewBuilder
    private func artworkCard(for asset: TMDBImageAsset, isPortrait: Bool) -> some View {
        let isFocused = focusedAssetPath == asset.filePath
        let isCurrent = isAssetActive(asset.filePath)
        let isMultiSelected = isAssetMultiSelected(asset.filePath)
        let ratio: CGFloat = isPortrait ? (2.0 / 3.0) : (16.0 / 9.0)
        let sizeParam = selectedTab == .backdrops ? "w780" : "w500"

        Button {
            if isMultipleArtworkEnabled {
                toggleMultiArtwork(asset.filePath)
            } else {
                applyArtwork(asset.filePath)
            }
        } label: {
            ZStack {
                Group {
                    if let url = TMDBService.shared.imageURL(path: asset.filePath, size: sizeParam) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: selectedTab == .logos ? .fit : .fill)
                                    .padding(selectedTab == .logos ? 16 : 0)
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
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Bottom-left "✓ Current" badge
                if isCurrent {
                    VStack {
                        Spacer()
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Current")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.white, in: Capsule())
                            .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                            .padding(8)

                            Spacer()
                        }
                    }
                }

                // Multi-artwork top-right selection circle
                if isMultipleArtworkEnabled {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: isMultiSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.7), radius: 4)
                                .padding(8)
                        }
                        Spacer()
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 3 : 0.8)
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .shadow(color: isFocused ? Color.white.opacity(0.14) : .black.opacity(0.35), radius: isFocused ? 14 : 6)
            .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedAssetPath, equals: asset.filePath)
    }

    // MARK: - Floating Bottom-Right Live Mini-Preview Card

    private var floatingMiniPreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Miniature Detail Screen Preview
            ZStack(alignment: .bottomLeading) {
                if let backdrop = previewBackdropPath,
                   let url = TMDBService.shared.imageURL(path: backdrop, size: "w780") {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 376, height: 190)
                                .clipped()
                        } else {
                            Color.auraSurface.frame(width: 376, height: 190)
                        }
                    }
                } else {
                    Color.auraSurface.frame(width: 376, height: 190)
                }

                LinearGradient(
                    stops: [
                        .init(color: Color.auraBackground.opacity(0.95), location: 0.0),
                        .init(color: Color.auraBackground.opacity(0.55), location: 0.55),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    colors: [Color.auraBackground.opacity(0.95), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        TitleLogoView(
                            title: title,
                            mediaType: mediaType,
                            tmdbId: tmdbId,
                            preloadedLogoPath: previewLogoPath,
                            maxWidth: 165,
                            maxHeight: 42,
                            fallbackFontSize: 16,
                            alignment: .leading
                        )

                        Text("4K • Dolby Vision • \(mediaType == "series" ? "Series" : "Movie")")
                            .font(.system(size: 7.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))

                        HStack(spacing: 4) {
                            HStack(spacing: 3) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 6))
                                Text("Play")
                                    .font(.system(size: 7.5, weight: .bold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.white, in: Capsule())

                            ForEach(["checkmark", "bookmark", "ellipsis"], id: \.self) { icon in
                                Image(systemName: icon)
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 14, height: 14)
                                    .background(Color.white.opacity(0.18), in: Circle())
                            }
                        }

                        if mediaType == "series" {
                            Text("Episodes")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.top, 4)

                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 58, height: 28)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 58, height: 28)
                            }
                        }
                    }

                    Spacer()

                    // Mini Poster card on right of preview
                    VStack(spacing: 4) {
                        if let poster = previewPosterPath,
                           let posterURL = TMDBService.shared.imageURL(path: poster, size: "w342") {
                            AsyncImage(url: posterURL) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .aspectRatio(2 / 3, contentMode: .fill)
                                        .frame(width: 68, height: 102)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                } else {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.auraSurface)
                                        .frame(width: 68, height: 102)
                                }
                            }
                        }
                        Text(title)
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                            .frame(width: 72)
                    }
                }
                .padding(14)
            }
            .frame(width: 376, height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
            )

            // Action instruction & metadata caption
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "hand.point.up.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text(previewActionLabel)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)

                Text(previewDimensionCaption)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
        .background(Color(red: 14 / 255, green: 16 / 255, blue: 22 / 255).opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.75), radius: 24, y: 8)
    }

    private var previewActionLabel: String {
        if let asset = focusedAsset {
            if isMultipleArtworkEnabled {
                return isAssetMultiSelected(asset.filePath) ? "Press to take it out" : "Press to add it"
            }
            return isAssetActive(asset.filePath) ? "Current artwork" : "Press to apply"
        }
        return "Press to apply"
    }

    private var previewDimensionCaption: String {
        if let asset = focusedAsset ?? currentAssets.first,
           let w = asset.width, let h = asset.height {
            let ext = asset.filePath.lowercased().hasSuffix(".png") ? "PNG" : "JPG"
            return "\(w) × \(h) · \(ext) · \(selectedSource.rawValue)"
        }
        return "\(posters.count) posters · \(backdrops.count) backdrops · \(selectedSource.rawValue)"
    }

    // MARK: - Logic & Persistence

    private func isAssetActive(_ path: String) -> Bool {
        switch selectedTab {
        case .posters: return activePosterPath == path
        case .seasonPosters: return activePosterPath == path
        case .backdrops: return activeBackdropPath == path
        case .logos: return activeLogoPath == path
        }
    }

    private func isAssetMultiSelected(_ path: String) -> Bool {
        switch selectedTab {
        case .posters, .seasonPosters: return selectedMultiPosters.contains(path)
        case .backdrops: return selectedMultiBackdrops.contains(path)
        case .logos: return activeLogoPath == path
        }
    }

    private func toggleMultiArtwork(_ path: String) {
        switch selectedTab {
        case .posters, .seasonPosters:
            if selectedMultiPosters.contains(path) {
                selectedMultiPosters.remove(path)
            } else {
                selectedMultiPosters.insert(path)
            }
        case .backdrops:
            if selectedMultiBackdrops.contains(path) {
                selectedMultiBackdrops.remove(path)
            } else {
                selectedMultiBackdrops.insert(path)
            }
        case .logos:
            applyArtwork(path)
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

            if mediaType == "series",
               let seriesDetail = try? await TMDBService.shared.fetchSeriesDetails(id: tmdbId) {
                seasonPosters = (seriesDetail.seasons ?? []).compactMap { season in
                    guard let poster = season.posterPath else { return nil }
                    return TMDBImageAsset(filePath: poster, iso6391: nil, aspectRatio: 0.667, width: 1000, height: 1500)
                }
            }

            if focusedAssetPath == nil {
                let targetPath = activePosterPath ?? posters.first?.filePath
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    focusedAssetPath = targetPath
                }
            }
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
        case .posters, .seasonPosters:
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
