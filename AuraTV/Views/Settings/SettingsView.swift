import SwiftUI
import SwiftData

// MARK: - Settings Categories

enum SettingsCategory: String, CaseIterable, Identifiable {
    case playback = "Playback"
    case subtitles = "Subtitles"
    case skipIntroCredits = "Skip Intro & Credits"
    case appearance = "Appearance"
    case library = "Library"
    case serversAccounts = "Servers & Accounts"
    case trakt = "Trakt"
    case artworkMetadata = "Artwork & Metadata"
    case about = "About"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .playback: return "play.rectangle"
        case .subtitles: return "captions.bubble"
        case .skipIntroCredits: return "forward.end"
        case .appearance: return "circle.lefthalf.filled"
        case .library: return "books.vertical"
        case .serversAccounts: return "list.bullet.rectangle"
        case .trakt: return "checkmark.circle"
        case .artworkMetadata: return "photo.on.rectangle"
        case .about: return "info.circle"
        }
    }

    var summarySubtitle: String {
        switch self {
        case .playback:
            return "How titles start, what plays next, and which player and audio Aura uses."
        case .subtitles:
            return "Languages, the look of the text, Arabic RTL shaping, and online subtitles."
        case .skipIntroCredits:
            return "What happens at intros, recaps, and end credits."
        case .appearance:
            return "Interface language, Home hero layout, Movies layout, and watched badges."
        case .library:
            return "Preferred quality, local watch history backup, and watchlist cleanup."
        case .serversAccounts:
            return "TMDB metadata key, AIOStreams manifest URL, and subtitle provider keys."
        case .trakt:
            return "Scrobbling and watched history sync settings."
        case .artworkMetadata:
            return "Transparent title logos, artwork language preferences, and subtitle auto-sync."
        case .about:
            return "AuraTV build details, video engine, and design specifications."
        }
    }
}

private struct SummaryTileItem: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

// MARK: - Settings View (2-Column Split Layout + Frosted Live Preview Card)

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var artworkOverrides: [CustomArtwork]
    @State private var viewModel = SettingsViewModel()

    @State private var addonLink = ""
    @State private var addonMessage = ""
    @State private var installingAddon = false
    @AppStorage("streamOrder") private var streamOrder = "Provider order"
    @AppStorage("hideDV") private var hideDV = false
    @AppStorage("hide3D") private var hide3D = false
    @AppStorage("hideCAM") private var hideCAM = false

    @State private var selectedCategory: SettingsCategory = .playback
    @State private var isEditingCategory: Bool = false
    @State private var showSavedAlert: Bool = false

    @FocusState private var focusedCategory: SettingsCategory?

    var body: some View {
        ZStack {
            Color.auraBackground.ignoresSafeArea()

            HStack(alignment: .top, spacing: 48) {
                // LEFT COLUMN: Settings Title + Vertical 9-Item Sidebar
                leftSidebarColumn
                    .frame(width: 430, alignment: .leading)

                // RIGHT COLUMN: Frosted Glass Live Preview Card / Category Controls
                rightDetailCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 75)
            .padding(.top, 96)
            .padding(.bottom, 50)
        }
        .defaultFocus($focusedCategory, .playback)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if !isEditingCategory && focusedCategory == nil {
                    focusedCategory = selectedCategory
                }
            }
        }
        .task {
            viewModel.loadSettings(context: modelContext)
            await viewModel.loadAmbientBannerIfNeeded()
        }
        .onChange(of: focusedCategory) { _, newCat in
            if let newCat, !isEditingCategory {
                selectedCategory = newCat
            }
        }
        .onExitCommand {
            if isEditingCategory {
                withAnimation(.easeOut(duration: 0.2)) {
                    isEditingCategory = false
                }
                focusedCategory = selectedCategory
            }
        }
        .alert("Settings Saved", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("All preferences and API settings have been saved.")
        }
    }

    // MARK: - Left Sidebar Column

    private var leftSidebarColumn: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("Settings")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
                .padding(.leading, 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(SettingsCategory.allCases) { category in
                        let isHighlighted = focusedCategory == category || (focusedCategory == nil && selectedCategory == category)

                        Button {
                            selectedCategory = category
                            withAnimation(.easeOut(duration: 0.2)) {
                                isEditingCategory = true
                            }
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: category.iconName)
                                    .font(.system(size: 19, weight: .medium))
                                    .frame(width: 26)

                                Text(category.rawValue)
                                    .font(.system(size: 19, weight: isHighlighted ? .semibold : .medium))

                                Spacer()
                            }
                            .foregroundStyle(isHighlighted ? Color.black : Color.white.opacity(0.92))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(
                                isHighlighted
                                ? Color.white
                                : Color.clear
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(AuraButtonStyle())
                        .focusEffectDisabled()
                        .focused($focusedCategory, equals: category)
                        .scaleEffect(focusedCategory == category ? 1.03 : 1.0)
                        .animation(.easeOut(duration: 0.16), value: focusedCategory)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Right Detail Frosted Glass Card

    private var rightDetailCard: some View {
        ZStack(alignment: .top) {
            // Card base container
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.auraSurface.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial.opacity(0.35))
                )

            // Blurred ambient artwork banner along the top
            ambientBannerHeader

            // Foreground preview summary OR category controls
            if isEditingCategory {
                categoryControlsPanel
            } else {
                categoryPreviewSummaryPanel
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var ambientBannerHeader: some View {
        GeometryReader { geo in
            ZStack {
                if let path = viewModel.ambientBannerBackdropPath,
                   let url = TMDBService.shared.imageURL(path: path, size: "w780") {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: 240)
                                .clipped()
                                .blur(radius: 16)
                                .opacity(0.45)
                        }
                    }
                } else {
                    LinearGradient(
                        colors: [Color.auraAccent.opacity(0.28), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: geo.size.width, height: 240)
                }

                // Bottom fade into the frosted glass body
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color.auraSurface.opacity(0.85), location: 0.72),
                        .init(color: Color.auraSurface, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: geo.size.width, height: 240)
        }
        .frame(height: 240)
    }

    // MARK: - Preview Summary Mode (Matches Video 2x2 Status Tile Card)

    private var categoryPreviewSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 26) {
            Spacer().frame(height: 110)

            // Icon + Category Title + 1-line description
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: selectedCategory.iconName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Text(selectedCategory.rawValue)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)

                Text(selectedCategory.summarySubtitle)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
            }

            // 2x2 Grid of Status Summary Tiles
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ],
                spacing: 14
            ) {
                ForEach(summaryTiles(for: selectedCategory)) { tile in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tile.label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))

                        Text(tile.value)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
            }

            Spacer()
        }
        .padding(42)
    }

    private func summaryTiles(for category: SettingsCategory) -> [SummaryTileItem] {
        switch category {
        case .playback:
            return [
                SummaryTileItem(label: "Resume", value: viewModel.resumePlaybackBehavior),
                SummaryTileItem(label: "Next episode", value: viewModel.nextEpisodeBehavior),
                SummaryTileItem(label: "Player engine", value: viewModel.playerEngineName),
                SummaryTileItem(label: "Audio", value: viewModel.audioOutputMode)
            ]
        case .subtitles:
            return [
                SummaryTileItem(label: "Turn on", value: viewModel.subtitleAutoMode),
                SummaryTileItem(
                    label: "Languages",
                    value: "\(viewModel.displayLanguageName(for: viewModel.subtitleLanguage)), \(viewModel.displayLanguageName(for: viewModel.secondarySubtitleLanguage))"
                ),
                SummaryTileItem(label: "Font", value: viewModel.subtitleFontName),
                SummaryTileItem(label: "Size", value: "\(Int(viewModel.subtitleFontSize)) pt")
            ]
        case .skipIntroCredits:
            return [
                SummaryTileItem(label: "Intro", value: viewModel.skipIntroMode),
                SummaryTileItem(label: "Recap", value: viewModel.skipRecapMode),
                SummaryTileItem(label: "Credits", value: viewModel.skipCreditsMode),
                SummaryTileItem(label: "Delay", value: "\(viewModel.skipDelaySeconds) s")
            ]
        case .appearance:
            return [
                SummaryTileItem(label: "Language", value: viewModel.displayLanguageName(for: viewModel.preferredLanguage)),
                SummaryTileItem(label: "Home layout", value: viewModel.homeHeroStyle),
                SummaryTileItem(label: "Movies layout", value: viewModel.moviesLayoutStyle),
                SummaryTileItem(label: "Watched indicator", value: viewModel.showWatchedIndicators ? "On" : "Off")
            ]
        case .library:
            return [
                SummaryTileItem(label: "Preferred quality", value: viewModel.preferredQuality),
                SummaryTileItem(label: "Watch history", value: "Local SwiftData"),
                SummaryTileItem(label: "Backup format", value: "JSON Export"),
                SummaryTileItem(label: "Metadata source", value: "TMDB v3")
            ]
        case .serversAccounts:
            return [
                SummaryTileItem(label: "TMDB API key", value: viewModel.tmdbApiKey.isEmpty ? "Not Set" : "Configured"),
                SummaryTileItem(label: "AIOStreams", value: viewModel.aioStreamsUrl.isEmpty ? "Not Set" : "Connected"),
                SummaryTileItem(label: "SubDL", value: viewModel.subdlApiKey.isEmpty ? "Optional" : "Configured"),
                SummaryTileItem(label: "OpenSubtitles", value: viewModel.openSubtitlesApiKey.isEmpty ? "Optional" : "Configured")
            ]
        case .trakt:
            return [
                SummaryTileItem(label: "Account", value: viewModel.traktUsername.isEmpty ? "Not Connected" : viewModel.traktUsername),
                SummaryTileItem(label: "Scrobble", value: viewModel.traktScrobbleEnabled ? "On" : "Off"),
                SummaryTileItem(label: "Auto-sync", value: "80% Threshold"),
                SummaryTileItem(label: "History merge", value: "Enabled")
            ]
        case .artworkMetadata:
            return [
                SummaryTileItem(label: "Home logos", value: viewModel.includeLogosInHome ? "On" : "Off"),
                SummaryTileItem(label: "Logo language", value: viewModel.preferredArtworkLanguage),
                SummaryTileItem(label: "Custom artwork", value: artworkOverrides.isEmpty ? "Default" : "\(artworkOverrides.count) titles"),
                SummaryTileItem(label: "Auto sync subtitles", value: viewModel.autoSyncSubtitles ? "On" : "Off")
            ]
        case .about:
            return [
                SummaryTileItem(label: "Version", value: "1.0.0"),
                SummaryTileItem(label: "Platform", value: "tvOS 18"),
                SummaryTileItem(label: "Engine", value: "AetherEngine"),
                SummaryTileItem(label: "Design", value: "Dark Cinema")
            ]
        }
    }

    // MARK: - Interactive Controls Panel (Opened on Category Click)

    private var categoryControlsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Top bar with Back button & Save CTA
            HStack {
                Button {
                    viewModel.saveSettings(context: modelContext)
                    withAnimation(.easeOut(duration: 0.2)) {
                        isEditingCategory = false
                    }
                    focusedCategory = selectedCategory
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                        Text("All Settings")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .modifier(SettingsFocusablePillModifier())
                }
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()

                Spacer()

                Button {
                    viewModel.saveSettings(context: modelContext)
                    showSavedAlert = true
                } label: {
                    Text("Save Changes")
                        .font(.system(size: 16, weight: .bold))
                        .modifier(SettingsPrimaryPillModifier())
                }
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()
            }

            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(selectedCategory.rawValue)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                Text(selectedCategory.summarySubtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.65))
            }

            // Full-Width Grouped Controls (No Truncated Segmented Controls)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    controlsContent(for: selectedCategory)

                    if let status = viewModel.statusMessage {
                        Text(status)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.green)
                            .padding(.top, 6)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(42)
    }

    @ViewBuilder
    private func controlsContent(for category: SettingsCategory) -> some View {
        switch category {
        case .playback:
            cycleSettingRow(title: "Resume Playback", value: viewModel.resumePlaybackBehavior) {
                viewModel.resumePlaybackBehavior = viewModel.nextValue(after: viewModel.resumePlaybackBehavior, in: SettingsViewModel.resumeOptions)
                viewModel.saveSettings(context: modelContext)
            }
            cycleSettingRow(title: "Next Episode", value: viewModel.nextEpisodeBehavior) {
                viewModel.nextEpisodeBehavior = viewModel.nextValue(after: viewModel.nextEpisodeBehavior, in: SettingsViewModel.nextEpisodeOptions)
                viewModel.saveSettings(context: modelContext)
            }
            cycleSettingRow(title: "Player Engine", value: viewModel.playerEngineName) {
                viewModel.playerEngineName = viewModel.nextValue(after: viewModel.playerEngineName, in: SettingsViewModel.playerEngineOptions)
                viewModel.saveSettings(context: modelContext)
            }
            cycleSettingRow(title: "Audio Output", value: viewModel.audioOutputMode) {
                viewModel.audioOutputMode = viewModel.nextValue(after: viewModel.audioOutputMode, in: SettingsViewModel.audioModeOptions)
                viewModel.saveSettings(context: modelContext)
            }
            cycleSettingRow(title: "Preferred Stream Quality", value: viewModel.preferredQuality) {
                viewModel.preferredQuality = viewModel.nextValue(after: viewModel.preferredQuality, in: SettingsViewModel.qualityOptions)
                viewModel.saveSettings(context: modelContext)
            }

        case .subtitles:
            cycleSettingRow(title: "Turn On Subtitles", value: viewModel.subtitleAutoMode) {
                viewModel.subtitleAutoMode = viewModel.nextValue(after: viewModel.subtitleAutoMode, in: SettingsViewModel.subtitleAutoOptions)
                viewModel.saveSettings(context: modelContext)
            }
            cycleSettingRow(title: "First Language", value: viewModel.displayLanguageName(for: viewModel.subtitleLanguage)) {
                let codes = SettingsViewModel.languageOptions.map(\.code)
                viewModel.subtitleLanguage = viewModel.nextValue(after: viewModel.subtitleLanguage, in: codes)
                viewModel.saveSettings(context: modelContext)
            }
            cycleSettingRow(title: "Second Language", value: viewModel.displayLanguageName(for: viewModel.secondarySubtitleLanguage)) {
                let codes = SettingsViewModel.languageOptions.map(\.code)
                viewModel.secondarySubtitleLanguage = viewModel.nextValue(after: viewModel.secondarySubtitleLanguage, in: codes)
                viewModel.saveSettings(context: modelContext)
            }
            cycleSettingRow(title: "Font Family", value: viewModel.subtitleFontName) {
                viewModel.subtitleFontName = viewModel.nextValue(after: viewModel.subtitleFontName, in: SettingsViewModel.fontNameOptions)
                viewModel.saveSettings(context: modelContext)
            }
            cycleSettingRow(title: "Font Size", value: "\(Int(viewModel.subtitleFontSize)) pt") {
                viewModel.subtitleFontSize = viewModel.nextValue(after: viewModel.subtitleFontSize, in: SettingsViewModel.subtitleSizeOptions)
                viewModel.saveSettings(context: modelContext)
            }
            cycleSettingRow(title: "Font Weight", value: viewModel.subtitleFontWeight) {
                viewModel.subtitleFontWeight = viewModel.nextValue(after: viewModel.subtitleFontWeight, in: SettingsViewModel.fontWeightOptions)
                viewModel.saveSettings(context: modelContext)
            }
            toggleSettingRow(
                title: "Fix Arabic RTL Alignment",
                subtitle: "Applies proper right-to-left directional embedding to Arabic subtitle lines.",
                isOn: $viewModel.fixArabicRTL
            )
            toggleSettingRow(
                title: "Fix Reversed Punctuation",
                subtitle: "Anchors commas, periods, dashes, and question marks on Arabic lines.",
                isOn: $viewModel.fixReversedPunctuation
            )

        case .skipIntroCredits:
            cycleSettingRow(title: "Skip Intro", value: viewModel.skipIntroMode) {
                viewModel.skipIntroMode = viewModel.nextValue(after: viewModel.skipIntroMode, in: SettingsViewModel.skipModeOptions)
                viewModel.saveSettings(context: modelContext)
            }
            cycleSettingRow(title: "Skip Recap", value: viewModel.skipRecapMode) {
                viewModel.skipRecapMode = viewModel.nextValue(after: viewModel.skipRecapMode, in: SettingsViewModel.skipModeOptions)
                viewModel.saveSettings(context: modelContext)
            }
            cycleSettingRow(title: "Skip Credits", value: viewModel.skipCreditsMode) {
                viewModel.skipCreditsMode = viewModel.nextValue(after: viewModel.skipCreditsMode, in: SettingsViewModel.skipModeOptions)
                viewModel.saveSettings(context: modelContext)
            }
            cycleSettingRow(title: "Delay Before Automatic Skip", value: "\(viewModel.skipDelaySeconds) s") {
                viewModel.skipDelaySeconds = viewModel.nextValue(after: viewModel.skipDelaySeconds, in: SettingsViewModel.skipDelayOptions)
                viewModel.saveSettings(context: modelContext)
            }
            toggleSettingRow(
                title: "Use IntroDB",
                subtitle: "Ask online database for community intro, recap, and credits markers.",
                isOn: $viewModel.useIntroDB
            )

        case .appearance:
            cycleSettingRow(title: "Home Hero Layout", value: viewModel.homeHeroStyle) {
                viewModel.homeHeroStyle = viewModel.nextValue(after: viewModel.homeHeroStyle, in: SettingsViewModel.homeLayoutOptions)
                viewModel.saveSettings(context: modelContext)
            }
            cycleSettingRow(title: "Movies Grid Layout", value: viewModel.moviesLayoutStyle) {
                viewModel.moviesLayoutStyle = viewModel.nextValue(after: viewModel.moviesLayoutStyle, in: SettingsViewModel.moviesLayoutOptions)
                viewModel.saveSettings(context: modelContext)
            }
            toggleSettingRow(
                title: "Show Watched Indicator",
                subtitle: "Displays a small checkmark badge on watched movie and series posters.",
                isOn: $viewModel.showWatchedIndicators
            )
            cycleSettingRow(title: "Interface Language", value: viewModel.displayLanguageName(for: viewModel.preferredLanguage)) {
                let codes = SettingsViewModel.languageOptions.map(\.code)
                viewModel.preferredLanguage = viewModel.nextValue(after: viewModel.preferredLanguage, in: codes)
                viewModel.saveSettings(context: modelContext)
            }

        case .library:
            textFieldSettingRow(title: "Backup File URL", placeholder: "https://…/history.json", text: $viewModel.backupURL, isSecure: false)
            Text("Use a direct HTTPS file URL you control. Export uploads with PUT and replaces that file. Import downloads with GET.")
            actionSettingRow(title: "Export Watch History (JSON)", icon: "square.and.arrow.up") {
                Task { await viewModel.transferBackup(exporting: true, context: modelContext) }
            }
            .disabled(viewModel.transferringBackup)
            actionSettingRow(title: "Import Watch History (JSON)", icon: "square.and.arrow.down") {
                Task { await viewModel.transferBackup(exporting: false, context: modelContext) }
            }
            .disabled(viewModel.transferringBackup)
            if viewModel.transferringBackup { ProgressView() }
            if let error = viewModel.error { Text(error).foregroundStyle(.red) }
            actionSettingRow(title: "Clear Watch History", icon: "trash") {
                viewModel.clearWatchHistory(context: modelContext)
            }
            actionSettingRow(title: "Clear Watchlist", icon: "bookmark.slash") {
                viewModel.clearWatchlist(context: modelContext)
            }

        case .serversAccounts:
            cycleSettingRow(title: "Stream order", value: streamOrder) {
                streamOrder = viewModel.nextValue(after: streamOrder, in: ["Provider order", "Arabic first", "Cached first", "Preferred quality"])
            }
            Toggle("Hide CAM when alternatives exist", isOn: $hideCAM)
            Toggle("Hide Dolby Vision when alternatives exist", isOn: $hideDV)
            Toggle("Hide 3D when alternatives exist", isOn: $hide3D)
            ForEach(AIOStreamsService.shared.addons) { addon in
                HStack {
                    Button(addon.name + (addon.enabled ? " · On" : " · Off")) {
                        if let i = AIOStreamsService.shared.addons.firstIndex(where: { $0.id == addon.id }) {
                            AIOStreamsService.shared.addons[i].enabled.toggle()
                        }
                    }
                    Button("Remove") { AIOStreamsService.shared.addons.removeAll { $0.id == addon.id } }
                }
            }
            textFieldSettingRow(title: "Additional Stremio add-on", placeholder: "Manifest link", text: $addonLink, isSecure: false)
            Button("Install add-on") {
                installingAddon = true
                Task {
                    defer { installingAddon = false }
                    do {
                        try await AIOStreamsService.shared.install(addonLink)
                        addonLink = ""
                        addonMessage = "Add-on installed."
                    } catch { addonMessage = error.localizedDescription }
                }
            }
            .disabled(installingAddon || addonLink.isEmpty)
            if !addonMessage.isEmpty { Text(addonMessage) }
            textFieldSettingRow(
                title: "TMDB API Key (v3)",
                placeholder: "Enter TMDB v3 API Key",
                text: $viewModel.tmdbApiKey,
                isSecure: true
            )
            textFieldSettingRow(
                title: "AIOStreams Manifest URL",
                placeholder: "https://aiostreams.example.com/manifest.json",
                text: $viewModel.aioStreamsUrl,
                isSecure: false
            )
            textFieldSettingRow(
                title: "SubDL API Key (Optional)",
                placeholder: "Enter SubDL API Key",
                text: $viewModel.subdlApiKey,
                isSecure: true
            )
            textFieldSettingRow(
                title: "OpenSubtitles API Key (Optional)",
                placeholder: "Enter OpenSubtitles REST API Key",
                text: $viewModel.openSubtitlesApiKey,
                isSecure: true
            )
            actionSettingRow(
                title: viewModel.isTestingConnection ? "Testing AIOStreams..." : "Test AIOStreams Manifest",
                icon: "network"
            ) {
                viewModel.saveSettings(context: modelContext)
                Task {
                    await viewModel.testAIOStreamsConnection()
                }
            }
            if let connectionStatus = viewModel.connectionTestStatus {
                Text(connectionStatus)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(connectionStatus.hasPrefix("Connected") ? Color.green : Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }

        case .trakt:
            textFieldSettingRow(
                title: "Trakt Username",
                placeholder: "Enter Trakt handle",
                text: $viewModel.traktUsername,
                isSecure: false
            )
            toggleSettingRow(
                title: "Scrobble to Trakt",
                subtitle: "Automatically updates Trakt progress and watched status at 80%.",
                isOn: $viewModel.traktScrobbleEnabled
            )

        case .artworkMetadata:
            toggleSettingRow(
                title: "Official TMDB Logos on Home",
                subtitle: "Uses transparent studio title artwork in the Home hero banner.",
                isOn: $viewModel.includeLogosInHome
            )
            cycleSettingRow(title: "Preferred Logo Language", value: viewModel.preferredArtworkLanguage) {
                viewModel.preferredArtworkLanguage = viewModel.nextValue(
                    after: viewModel.preferredArtworkLanguage,
                    in: SettingsViewModel.artworkLanguageOptions
                )
                viewModel.saveSettings(context: modelContext)
            }
            toggleSettingRow(
                title: "Auto-Sync External Subtitles",
                subtitle: "Aligns downloaded SRT/VTT timing automatically when opening playback.",
                isOn: $viewModel.autoSyncSubtitles
            )
            actionSettingRow(
                title: "Restore All Default Artwork (\(artworkOverrides.count))",
                icon: "arrow.uturn.backward"
            ) {
                viewModel.clearCustomArtwork(context: modelContext)
            }

        case .about:
            infoRow(title: "Application", value: "AuraTV 1.0.0")
            infoRow(title: "Target Platform", value: "Apple TV 4K (tvOS 18+)")
            infoRow(title: "Media Playback", value: "AetherEngine (4K HDR10+ / Dolby Vision / TrueHD)")
            infoRow(title: "Metadata & Streams", value: "TMDB v3 • AIOStreams • Wyzie / SubDL")
        }
    }

    // MARK: - Full-Width Row Builders

    private func cycleSettingRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                HStack(spacing: 8) {
                    Text(value)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .modifier(SettingsFocusableRowModifier())
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
    }

    private func toggleSettingRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .onChange(of: isOn.wrappedValue) { _, _ in
            viewModel.saveSettings(context: modelContext)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func textFieldSettingRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            if isSecure {
                SecureField(placeholder, text: text)
                    .font(.system(size: 18))
                    .padding(14)
                    .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            } else {
                TextField(placeholder, text: text)
                    .font(.system(size: 18))
                    .padding(14)
                    .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func actionSettingRow(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .modifier(SettingsFocusableRowModifier())
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
            Spacer()
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Focus Helpers for Settings Right Panel

private struct SettingsFocusableRowModifier: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .background(
                Color.white.opacity(isFocused ? 0.16 : 0.06),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 2.5 : 1)
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

private struct SettingsFocusablePillModifier: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(isFocused ? Color.white : Color.white.opacity(0.14), in: Capsule())
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

private struct SettingsPrimaryPillModifier: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.black)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(Color.white, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(isFocused ? Color.white : .clear, lineWidth: 2.5)
                    .padding(-4)
            )
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}
