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
    case quickSetup = "Quick Setup / QR"
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
        case .quickSetup: return "qrcode"
        case .about: return "info.circle"
        }
    }

    var summarySubtitle: String {
        switch self {
        case .playback:
            return "How titles start, what plays next, and which player and audio Aura uses."
        case .subtitles:
            return "Languages, Mini LED-safe look of the text, custom fonts, and online subtitles."
        case .skipIntroCredits:
            return "What happens at intros, recaps and end credits."
        case .appearance:
            return "Interface language, Home layout, Movies layout, and spoiler protection."
        case .library:
            return "Preferred quality, local watch history backup, and watchlist cleanup."
        case .serversAccounts:
            return "TMDB, AIOStreams, Stremio, Nuvio addons, MDBList ratings, and subtitle keys."
        case .trakt:
            return "Scrobbling and watched history sync settings."
        case .artworkMetadata:
            return "Transparent title logos, artwork language preferences, and subtitle auto-sync."
        case .quickSetup:
            return "Paste any Stremio, AIOStreams, or Nuvio manifest URL directly or scan QR from phone."
        case .about:
            return "AuraTV build details, video engine, and design specifications."
        }
    }
}

private enum SettingsRightRoute: Hashable {
    case summary
    case categoryDetail
    case subtitlesStylePreview
    case subtitlesSizePosition
    case subtitlesCustomFonts
    case subtitlesFirstLanguage
    case subtitlesSecondLanguage
}

private enum RightFocusTarget: Hashable {
    case backButton
    case saveButton
    case summaryCard(Int)
    case openAllButton
    case detailFirstControl
}

private struct SummaryCardDescriptor: Identifiable {
    let index: Int
    let label: String
    let value: String
    let targetRoute: SettingsRightRoute?
    let opensPhoneQR: Bool

    var id: Int { index }

    init(
        index: Int,
        label: String,
        value: String,
        targetRoute: SettingsRightRoute? = .categoryDetail,
        opensPhoneQR: Bool = false
    ) {
        self.index = index
        self.label = label
        self.value = value
        self.targetRoute = targetRoute
        self.opensPhoneQR = opensPhoneQR
    }
}

// MARK: - Settings View (Reference 2-Column Split Layout + Sub-Screens)

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var artworkOverrides: [CustomArtwork]
    @State private var viewModel = SettingsViewModel()

    @State private var selectedCategory: SettingsCategory = .playback
    @State private var rightRoute: SettingsRightRoute = .summary
    @State private var showSavedAlert: Bool = false
    @State private var showPhoneQRSetup: Bool = false

    @FocusState private var focusedCategory: SettingsCategory?
    @FocusState private var focusedRightTarget: RightFocusTarget?

    private let summarySurfaceColor = Color(red: 22 / 255, green: 24 / 255, blue: 31 / 255)

    var body: some View {
        ZStack {
            AuraDynamicBackgroundView(
                styleSetting: viewModel.backgroundStyle,
                fallbackBackdropURL: viewModel.ambientBannerBackdropPath.flatMap {
                    TMDBService.shared.imageURL(path: $0, size: "w780")
                }
            )

            HStack(alignment: .top, spacing: 54) {
                // LEFT COLUMN: 52pt Bold Settings Title + 28-29pt Pill Sidebar
                leftSidebarColumn
                    .frame(width: 566, alignment: .leading)
                    .focusSection()

                // RIGHT COLUMN: Reference Summary Container -> Clean Sub-Screens
                rightDetailCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .focusSection()
            }
            .padding(.horizontal, 96)
            .padding(.top, 120)
            .padding(.bottom, 90)
        }
        .ignoresSafeArea()
        .defaultFocus($focusedCategory, .playback)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if focusedCategory == nil && focusedRightTarget == nil {
                    focusedCategory = selectedCategory
                }
            }
        }
        .task {
            viewModel.loadSettings(context: modelContext)
            await viewModel.loadAmbientBannerIfNeeded()
        }
        .onChange(of: focusedCategory) { _, newCat in
            if let newCat {
                selectedCategory = newCat
                if rightRoute != .summary {
                    rightRoute = .summary
                }
            }
        }
        .alert("Settings Saved", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("All preferences and manifest settings have been saved.")
        }
        .sheet(isPresented: $showPhoneQRSetup) {
            PhoneQRSetupView(settingsViewModel: viewModel) {
                viewModel.loadSettings(context: modelContext)
            }
        }
        .onDisappear {
            viewModel.saveSettings(context: modelContext)
        }
    }

    // MARK: - Left Sidebar Column (tvOS Reference Scale: 52pt Title, 28pt Rows)

    private var leftSidebarColumn: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("Settings")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(.white)
                .padding(.leading, 14)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(SettingsCategory.allCases.filter { $0 != .quickSetup }) { category in
                        let isHighlighted = focusedCategory == category || (focusedCategory == nil && selectedCategory == category)

                        Button {
                            selectedCategory = category
                            withAnimation(.easeOut(duration: 0.16)) {
                                rightRoute = .categoryDetail
                            }
                            DispatchQueue.main.async {
                                focusedRightTarget = .detailFirstControl
                            }
                        } label: {
                            HStack(spacing: 20) {
                                Image(systemName: category.iconName)
                                    .font(.system(size: 27, weight: .medium))
                                    .frame(width: 36)

                                Text(category.rawValue)
                                    .font(.system(size: 28, weight: isHighlighted ? .semibold : .medium))
                                    .lineLimit(1)

                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(isHighlighted ? Color.black : Color.white.opacity(0.92))
                            .padding(.horizontal, 26)
                            .padding(.vertical, 19)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                isHighlighted
                                ? Color.white
                                : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(AuraButtonStyle())
                        .focusEffectDisabled()
                        .focused($focusedCategory, equals: category)
                        .auraLeftEdgeSidebarTrigger()
                        .scaleEffect(focusedCategory == category ? 1.02 : 1.0)
                        .animation(.easeOut(duration: 0.14), value: focusedCategory)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Right Detail Container (#16181F at 92% Opacity, Zero Blur Lag)

    private var rightDetailCard: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.auraCardSurface)

            ambientBannerHeader

            switch rightRoute {
            case .summary:
                categorySummaryPanel
            case .categoryDetail:
                categoryDetailPanel
            case .subtitlesStylePreview:
                subtitlesStylePreviewScreen
            case .subtitlesSizePosition:
                subtitlesSizePositionScreen
            case .subtitlesCustomFonts:
                subtitlesCustomFontsScreen
            case .subtitlesFirstLanguage:
                subtitlesLanguagePickerScreen(title: "First language", selection: $viewModel.subtitleLanguage)
            case .subtitlesSecondLanguage:
                subtitlesLanguagePickerScreen(title: "Second language", selection: $viewModel.secondarySubtitleLanguage)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .onExitCommand {
            handleRightPaneExit()
        }
    }

    private func handleRightPaneExit() {
        switch rightRoute {
        case .subtitlesStylePreview, .subtitlesSizePosition, .subtitlesCustomFonts, .subtitlesFirstLanguage, .subtitlesSecondLanguage:
            withAnimation(.easeOut(duration: 0.16)) {
                rightRoute = .categoryDetail
            }
            DispatchQueue.main.async {
                focusedRightTarget = .detailFirstControl
            }
        case .categoryDetail:
            withAnimation(.easeOut(duration: 0.16)) {
                rightRoute = .summary
            }
            DispatchQueue.main.async {
                focusedRightTarget = .summaryCard(0)
            }
        case .summary:
            focusedCategory = selectedCategory
        }
    }

    private var settingsArtworkURL: URL? {
        if let recent = artworkOverrides.filter({ $0.customBackdropPath != nil }).max(by: { $0.updatedAt < $1.updatedAt }),
           let url = TMDBService.shared.imageURL(path: recent.customBackdropPath, size: "w1280") {
            return url
        }
        return AppThemeCoordinator.shared.focusedBackdropURL
            ?? TMDBService.shared.imageURL(path: viewModel.ambientBannerBackdropPath, size: "w1280")
    }

    @ViewBuilder
    private var ambientBannerHeader: some View {
        GeometryReader { geo in
            ZStack {
                if let url = settingsArtworkURL {
                    AuraCachedImage(url: url, targetSize: CGSize(width: 960, height: 260)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: 260)
                            .clipped()
                            .opacity(0.36)
                    } placeholder: {
                        Color.clear.frame(width: geo.size.width, height: 260)
                    }
                } else {
                    LinearGradient(
                        colors: [Color.auraAccent.opacity(0.24), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: geo.size.width, height: 260)
                }

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: summarySurfaceColor.opacity(0.82), location: 0.68),
                        .init(color: summarySurfaceColor, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: geo.size.width, height: 260)
        }
        .frame(height: 260)
    }

    // MARK: - Reference Summary View (Top Banner + Title + 2x2 Interactive Summary Cards)

    private var categorySummaryPanel: some View {
        VStack(alignment: .leading, spacing: 26) {
            Spacer().frame(height: 112)

            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: selectedCategory.iconName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Text(selectedCategory.rawValue)
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(.white)

                Text(selectedCategory.summarySubtitle)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(2)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ],
                spacing: 16
            ) {
                ForEach(summaryCards(for: selectedCategory)) { card in
                    let isFocused = focusedRightTarget == .summaryCard(card.index)

                    Button {
                        if card.opensPhoneQR {
                            showPhoneQRSetup = true
                        } else if let target = card.targetRoute {
                            withAnimation(.easeOut(duration: 0.16)) {
                                rightRoute = target
                            }
                            DispatchQueue.main.async {
                                focusedRightTarget = .detailFirstControl
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(card.label)
                                .font(.system(size: 21, weight: .regular))
                                .foregroundStyle(isFocused ? Color.black.opacity(0.65) : Color.white.opacity(0.58))

                            Text(card.value)
                                .font(.system(size: 27, weight: .semibold))
                                .foregroundStyle(isFocused ? Color.black : Color.white)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(isFocused ? Color.white : Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 2.5 : 1)
                        )
                        .scaleEffect(isFocused ? 1.02 : 1.0)
                        .animation(.easeOut(duration: 0.14), value: focusedRightTarget)
                    }
                    .buttonStyle(AuraButtonStyle())
                    .focusEffectDisabled()
                    .focused($focusedRightTarget, equals: .summaryCard(card.index))
                }
            }

            if selectedCategory != .about {
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        rightRoute = .categoryDetail
                    }
                    DispatchQueue.main.async {
                        focusedRightTarget = .detailFirstControl
                    }
                } label: {
                    let isFocused = focusedRightTarget == .openAllButton
                    HStack {
                        Text(openDetailButtonTitle(for: selectedCategory))
                            .font(.system(size: 24, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundStyle(isFocused ? Color.black : Color.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(isFocused ? Color.white : Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 2.5 : 1)
                    )
                    .scaleEffect(isFocused ? 1.02 : 1.0)
                    .animation(.easeOut(duration: 0.14), value: focusedRightTarget)
                }
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()
                .focused($focusedRightTarget, equals: .openAllButton)
            }

            Spacer()
        }
        .padding(44)
    }

    private func openDetailButtonTitle(for category: SettingsCategory) -> String {
        switch category {
        case .subtitles:
            return "Style & Preview, Custom Fonts & Languages"
        case .quickSetup:
            return "Paste Manifest URL Directly / QR Setup"
        default:
            return "Configure \(category.rawValue)"
        }
    }

    private func summaryCards(for category: SettingsCategory) -> [SummaryCardDescriptor] {
        switch category {
        case .playback:
            return [
                SummaryCardDescriptor(index: 0, label: "Resume", value: viewModel.resumePlaybackBehavior),
                SummaryCardDescriptor(index: 1, label: "Next episode", value: viewModel.nextEpisodeBehavior),
                SummaryCardDescriptor(index: 2, label: "Player engine", value: viewModel.playerEngineName),
                SummaryCardDescriptor(index: 3, label: "Audio", value: viewModel.audioOutputMode)
            ]
        case .subtitles:
            return [
                SummaryCardDescriptor(index: 0, label: "Turn on", value: viewModel.subtitleAutoMode, targetRoute: .categoryDetail),
                SummaryCardDescriptor(
                    index: 1,
                    label: "Languages",
                    value: "\(viewModel.displayLanguageName(for: viewModel.subtitleLanguage)), \(viewModel.displayLanguageName(for: viewModel.secondarySubtitleLanguage))",
                    targetRoute: .subtitlesFirstLanguage
                ),
                SummaryCardDescriptor(index: 2, label: "Font", value: "\(viewModel.subtitleFontName) · \(viewModel.subtitleFontWeight)", targetRoute: .subtitlesCustomFonts),
                SummaryCardDescriptor(index: 3, label: "Size", value: "\(Int(viewModel.subtitleFontSize)) pt", targetRoute: .subtitlesSizePosition)
            ]
        case .skipIntroCredits:
            return [
                SummaryCardDescriptor(index: 0, label: "Intro", value: viewModel.skipIntroMode),
                SummaryCardDescriptor(index: 1, label: "Recap", value: viewModel.skipRecapMode),
                SummaryCardDescriptor(index: 2, label: "Overlay", value: viewModel.skipCreditsMode),
                SummaryCardDescriptor(index: 3, label: "Delay", value: "\(viewModel.skipDelaySeconds) s")
            ]
        case .appearance:
            return [
                SummaryCardDescriptor(index: 0, label: "Language", value: viewModel.displayLanguageName(for: viewModel.preferredLanguage)),
                SummaryCardDescriptor(index: 1, label: "Home", value: viewModel.homeHeroStyle),
                SummaryCardDescriptor(index: 2, label: "Movies", value: viewModel.moviesLayoutStyle),
                SummaryCardDescriptor(index: 3, label: "Watched indicator", value: viewModel.showWatchedIndicators ? "On" : "Off")
            ]
        case .library:
            return [
                SummaryCardDescriptor(index: 0, label: "Preferred quality", value: viewModel.preferredQuality),
                SummaryCardDescriptor(index: 1, label: "Watch history", value: "Local SwiftData"),
                SummaryCardDescriptor(index: 2, label: "Backup format", value: "JSON Export"),
                SummaryCardDescriptor(index: 3, label: "Metadata source", value: "TMDB v3")
            ]
        case .serversAccounts:
            return [
                SummaryCardDescriptor(index: 0, label: "TMDB API key", value: viewModel.tmdbApiKey.isEmpty ? "Not Set" : "Configured"),
                SummaryCardDescriptor(index: 1, label: "AIOStreams / Stremio", value: viewModel.aioStreamsUrl.isEmpty ? "Not Set" : "Connected"),
                SummaryCardDescriptor(index: 2, label: "Nuvio / Addons", value: viewModel.configuredManifestURLs.count > 1 ? "\(viewModel.configuredManifestURLs.count) Addons" : "Add Optional"),
                SummaryCardDescriptor(index: 3, label: "MDBList & Subtitles", value: viewModel.mdblistApiKey.isEmpty ? "Optional" : "Configured")
            ]
        case .trakt:
            return [
                SummaryCardDescriptor(index: 0, label: "Account", value: viewModel.traktUsername.isEmpty ? "Not Connected" : viewModel.traktUsername),
                SummaryCardDescriptor(index: 1, label: "Scrobble", value: viewModel.traktScrobbleEnabled ? "On" : "Off"),
                SummaryCardDescriptor(index: 2, label: "Auto-sync", value: "80% Threshold"),
                SummaryCardDescriptor(index: 3, label: "History merge", value: "Enabled")
            ]
        case .artworkMetadata:
            return [
                SummaryCardDescriptor(index: 0, label: "Home logos", value: viewModel.includeLogosInHome ? "On" : "Off"),
                SummaryCardDescriptor(index: 1, label: "Logo language", value: viewModel.preferredArtworkLanguage),
                SummaryCardDescriptor(index: 2, label: "Custom artwork", value: artworkOverrides.isEmpty ? "Default" : "\(artworkOverrides.count) titles"),
                SummaryCardDescriptor(index: 3, label: "Auto sync subtitles", value: viewModel.autoSyncSubtitles ? "On" : "Off")
            ]
        case .quickSetup:
            return [
                SummaryCardDescriptor(index: 0, label: "Phone QR Setup", value: "Scan QR Code", targetRoute: nil, opensPhoneQR: true),
                SummaryCardDescriptor(index: 1, label: "AIOStreams / Stremio URLs", value: viewModel.aioStreamsUrl.isEmpty ? "Paste Manifest..." : "Configured"),
                SummaryCardDescriptor(index: 2, label: "Nuvio / Addon URLs", value: viewModel.aioStreamsAdditionalUrls.isEmpty ? "Add Addon..." : "Configured"),
                SummaryCardDescriptor(index: 3, label: "MDBList & AI Key", value: viewModel.mdblistApiKey.isEmpty && viewModel.aiTranslationApiKey.isEmpty ? "Optional" : "Configured")
            ]
        case .about:
            return [
                SummaryCardDescriptor(index: 0, label: "Application", value: "AuraTV 1.0.0"),
                SummaryCardDescriptor(index: 1, label: "Platform", value: "tvOS 18+"),
                SummaryCardDescriptor(index: 2, label: "Engine", value: "AetherEngine"),
                SummaryCardDescriptor(index: 3, label: "Design", value: "Dark Cinema")
            ]
        }
    }

    // MARK: - Full-Width Category Detail Panel

    private var categoryDetailPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            detailHeaderBar(
                title: selectedCategory.rawValue,
                subtitle: selectedCategory.summarySubtitle,
                backTitle: "Summary",
                backAction: {
                    withAnimation(.easeOut(duration: 0.16)) {
                        rightRoute = .summary
                    }
                    DispatchQueue.main.async {
                        focusedRightTarget = .summaryCard(0)
                    }
                }
            )

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    controlsContent(for: selectedCategory)

                    if let status = viewModel.statusMessage {
                        Text(status)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.green)
                            .padding(.top, 6)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(44)
    }

    private func detailHeaderBar(
        title: String,
        subtitle: String,
        backTitle: String,
        backAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: backAction) {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .bold))
                        Text(backTitle)
                            .font(.system(size: 21, weight: .semibold))
                    }
                    .modifier(SettingsFocusablePillModifier())
                }
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()
                .focused($focusedRightTarget, equals: .backButton)

                Spacer()

                Button {
                    viewModel.saveSettings(context: modelContext)
                    showSavedAlert = true
                } label: {
                    Text("Save Changes")
                        .font(.system(size: 21, weight: .bold))
                        .modifier(SettingsPrimaryPillModifier())
                }
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()
                .focused($focusedRightTarget, equals: .saveButton)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
    }

    // MARK: - Subtitles Dedicated Sub-Screens

    private var subtitlesStylePreviewScreen: some View {
        VStack(alignment: .leading, spacing: 22) {
            detailHeaderBar(
                title: "Style & Preview",
                subtitle: "Low-bloom Mini LED colors, opacity, and subtle dark drop shadow.",
                backTitle: "Subtitles",
                backAction: {
                    viewModel.saveSettings(context: modelContext)
                    withAnimation(.easeOut(duration: 0.16)) { rightRoute = .categoryDetail }
                    DispatchQueue.main.async { focusedRightTarget = .detailFirstControl }
                }
            )

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    // Live Mini LED Preview Card
                    let previewStyle = SubtitleStyle(
                        fontSize: viewModel.subtitleFontSize,
                        fontWeight: viewModel.subtitleFontWeight,
                        fontName: viewModel.subtitleFontName,
                        textColor: viewModel.subtitleTextColor,
                        textOpacity: viewModel.subtitleTextOpacity,
                        backgroundOpacity: viewModel.subtitleBackgroundOpacity,
                        bottomOffset: viewModel.subtitleBottomOffset
                    )

                    VStack(spacing: 12) {
                        Text("Mini LED Live Preview")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))

                        VStack(spacing: 8) {
                            Text(SubtitleProcessor.process(
                                text: "هذه ترجمة عربية مصممة لشاشات Mini LED بدون توهج.",
                                isArabic: true,
                                fixRTL: viewModel.fixArabicRTL,
                                fixReversedPunctuation: viewModel.fixReversedPunctuation
                            ))
                            .font(previewStyle.font)
                            .foregroundStyle(previewStyle.colorValue)
                            .shadow(color: .black.opacity(0.92), radius: 3, x: 0, y: 2)

                            Text("Sharp cinema subtitles with zero Mini LED blooming.")
                                .font(previewStyle.font)
                                .foregroundStyle(previewStyle.colorValue)
                                .shadow(color: .black.opacity(0.92), radius: 3, x: 0, y: 2)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                        .background(
                            Color.black.opacity(max(viewModel.subtitleBackgroundOpacity, 0.0)),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                    // Mini LED Low-Bloom Presets
                    ForEach(Array(SubtitleStyle.miniLEDPresets.enumerated()), id: \.element.id) { idx, preset in
                        let isSelected = viewModel.subtitleTextColor.lowercased() == preset.name.lowercased()
                        let row = SettingsPresetRowButton(
                            title: preset.name,
                            subtitle: preset.subtitle,
                            swatchColor: preset.color,
                            isSelected: isSelected
                        ) {
                            viewModel.subtitleTextColor = preset.name
                            viewModel.saveSettings(context: modelContext)
                        }

                        if idx == 0 {
                            row.focused($focusedRightTarget, equals: .detailFirstControl)
                        } else {
                            row
                        }
                    }

                    // Subtitle Opacity Slider Row (D-pad Left/Right or - / + buttons)
                    subtitleOpacitySliderRow

                    cycleSettingRow(
                        title: "Background Box Opacity",
                        value: "\(Int(viewModel.subtitleBackgroundOpacity * 100))%"
                    ) {
                        viewModel.subtitleBackgroundOpacity = viewModel.nextValue(
                            after: viewModel.subtitleBackgroundOpacity,
                            in: SettingsViewModel.subtitleBackgroundOpacityOptions
                        )
                        viewModel.saveSettings(context: modelContext)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(44)
    }

    private var subtitleOpacitySliderRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Subtitle Opacity")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("75%–80% keeps subtitles crisp without blooming on Mini LED displays.")
                        .font(.system(size: 19))
                        .foregroundStyle(.white.opacity(0.64))
                }
                Spacer()
                Text("\(Int((viewModel.subtitleTextOpacity * 100).rounded()))%")
                    .font(.system(size: 25, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
            }

            HStack(spacing: 16) {
                Button("-5%") {
                    viewModel.subtitleTextOpacity = max(0.40, viewModel.subtitleTextOpacity - 0.05)
                    viewModel.saveSettings(context: modelContext)
                }
                .font(.system(size: 20, weight: .semibold))
                .modifier(SettingsFocusablePillModifier())
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()

                GeometryReader { geo in
                    let fraction = CGFloat(min(max((viewModel.subtitleTextOpacity - 0.40) / 0.60, 0), 1))
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                            .frame(height: 10)
                        Capsule()
                            .fill(Color.white)
                            .frame(width: max(18, geo.size.width * fraction), height: 10)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 28)

                Button("+5%") {
                    viewModel.subtitleTextOpacity = min(1.00, viewModel.subtitleTextOpacity + 0.05)
                    viewModel.saveSettings(context: modelContext)
                }
                .font(.system(size: 20, weight: .semibold))
                .modifier(SettingsFocusablePillModifier())
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var subtitlesSizePositionScreen: some View {
        VStack(alignment: .leading, spacing: 22) {
            detailHeaderBar(
                title: "Size & Position",
                subtitle: "Adjust text size, weight, and bottom safe-area offset.",
                backTitle: "Subtitles",
                backAction: {
                    viewModel.saveSettings(context: modelContext)
                    withAnimation(.easeOut(duration: 0.16)) { rightRoute = .categoryDetail }
                    DispatchQueue.main.async { focusedRightTarget = .detailFirstControl }
                }
            )

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    cycleSettingRow(title: "Font Size", value: "\(Int(viewModel.subtitleFontSize)) pt") {
                        viewModel.subtitleFontSize = viewModel.nextValue(
                            after: viewModel.subtitleFontSize,
                            in: SettingsViewModel.subtitleSizeOptions
                        )
                        viewModel.saveSettings(context: modelContext)
                    }
                    .focused($focusedRightTarget, equals: .detailFirstControl)

                    cycleSettingRow(title: "Font Weight", value: viewModel.subtitleFontWeight) {
                        viewModel.subtitleFontWeight = viewModel.nextValue(
                            after: viewModel.subtitleFontWeight,
                            in: SettingsViewModel.fontWeightOptions
                        )
                        viewModel.saveSettings(context: modelContext)
                    }

                    cycleSettingRow(title: "Bottom Offset", value: "\(Int(viewModel.subtitleBottomOffset)) pt") {
                        viewModel.subtitleBottomOffset = viewModel.nextValue(
                            after: viewModel.subtitleBottomOffset,
                            in: SettingsViewModel.subtitleBottomOffsetOptions
                        )
                        viewModel.saveSettings(context: modelContext)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(44)
    }

    private var subtitlesCustomFontsScreen: some View {
        VStack(alignment: .leading, spacing: 22) {
            detailHeaderBar(
                title: "Custom Fonts",
                subtitle: "Choose a bundled font or import a TTF or OTF from your phone.",
                backTitle: "Subtitles",
                backAction: {
                    viewModel.saveSettings(context: modelContext)
                    withAnimation(.easeOut(duration: 0.16)) { rightRoute = .categoryDetail }
                    DispatchQueue.main.async { focusedRightTarget = .detailFirstControl }
                }
            )

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    actionSettingRow(title: "Import from Phone", icon: "qrcode") { showPhoneQRSetup = true }
                    ForEach(Array(SettingsViewModel.fontNameOptions.enumerated()), id: \.element) { idx, fontName in
                        let isSelected = viewModel.subtitleFontName == fontName
                        let sampleStyle = SubtitleStyle(
                            fontSize: 28,
                            fontWeight: viewModel.subtitleFontWeight,
                            fontName: fontName,
                            textColor: viewModel.subtitleTextColor,
                            textOpacity: viewModel.subtitleTextOpacity
                        )

                        let btn = SettingsFontRowButton(
                            fontName: fontName,
                            sampleFont: sampleStyle.font,
                            sampleColor: sampleStyle.colorValue,
                            isSelected: isSelected
                        ) {
                            viewModel.subtitleFontName = fontName
                            viewModel.saveSettings(context: modelContext)
                        }

                        if idx == 0 {
                            btn.focused($focusedRightTarget, equals: .detailFirstControl)
                        } else {
                            btn
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(44)
    }

    private func subtitlesLanguagePickerScreen(title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            detailHeaderBar(
                title: title,
                subtitle: "Choose preferred subtitle download & selection priority.",
                backTitle: "Subtitles",
                backAction: {
                    viewModel.saveSettings(context: modelContext)
                    withAnimation(.easeOut(duration: 0.16)) { rightRoute = .categoryDetail }
                    DispatchQueue.main.async { focusedRightTarget = .detailFirstControl }
                }
            )

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(Array(SettingsViewModel.languageOptions.enumerated()), id: \.element.code) { idx, lang in
                        let isSelected = selection.wrappedValue == lang.code
                        let btn = SettingsLanguageRowButton(
                            name: lang.name,
                            code: lang.code.uppercased(),
                            isSelected: isSelected
                        ) {
                            selection.wrappedValue = lang.code
                            viewModel.saveSettings(context: modelContext)
                        }

                        if idx == 0 {
                            btn.focused($focusedRightTarget, equals: .detailFirstControl)
                        } else {
                            btn
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(44)
    }

    // MARK: - Controls Content per Category

    @ViewBuilder
    private func controlsContent(for category: SettingsCategory) -> some View {
        switch category {
        case .playback:
            cycleSettingRow(title: "Resume Playback", value: viewModel.resumePlaybackBehavior) {
                viewModel.resumePlaybackBehavior = viewModel.nextValue(after: viewModel.resumePlaybackBehavior, in: SettingsViewModel.resumeOptions)
                viewModel.saveSettings(context: modelContext)
            }
            .focused($focusedRightTarget, equals: .detailFirstControl)
            cycleSettingRow(title: "Rewind on Resume", value: viewModel.displayRewindOnResume(viewModel.rewindOnResumeSeconds)) {
                viewModel.rewindOnResumeSeconds = viewModel.nextValue(after: viewModel.rewindOnResumeSeconds, in: SettingsViewModel.rewindOnResumeOptions)
                viewModel.saveSettings(context: modelContext)
            }
            cycleSettingRow(title: "Next Episode", value: viewModel.nextEpisodeBehavior) {
                viewModel.nextEpisodeBehavior = viewModel.nextValue(after: viewModel.nextEpisodeBehavior, in: SettingsViewModel.nextEpisodeOptions)
                viewModel.saveSettings(context: modelContext)
            }
            toggleSettingRow(
                title: "Play at Once (Auto-Play First Stream)",
                subtitle: "Preserves exact AIOStreams order and starts playing the first returned stream automatically.",
                isOn: $viewModel.playAtOnce
            )
            cycleSettingRow(title: "Player Engine", value: viewModel.playerEngineName) {
                viewModel.playerEngineName = viewModel.nextValue(after: viewModel.playerEngineName, in: SettingsViewModel.playerEngineOptions)
                viewModel.saveSettings(context: modelContext)
            }
            cycleSettingRow(title: "External Player", value: viewModel.externalPlayer) {
                viewModel.externalPlayer = viewModel.nextValue(after: viewModel.externalPlayer, in: SettingsViewModel.externalPlayerOptions)
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
            cycleSettingRow(title: "Buffer Ahead", value: viewModel.bufferAheadMode) {
                viewModel.bufferAheadMode = viewModel.nextValue(after: viewModel.bufferAheadMode, in: SettingsViewModel.bufferAheadOptions)
                viewModel.saveSettings(context: modelContext)
            }
            audioSyncOffsetRow
            toggleSettingRow(
                title: "Dolby Vision Enabled",
                subtitle: "Present Dolby Vision on compatible displays.",
                isOn: $viewModel.dolbyVisionEnabled
            )
            toggleSettingRow(
                title: "Dolby Vision Profile 7 to HDR10 Fallback",
                subtitle: "Convert Profile 7 enhancement streams to HDR10 for incompatible displays.",
                isOn: $viewModel.dolbyVisionP7ToHDR10Fallback
            )
            toggleSettingRow(
                title: "HDR Enabled",
                subtitle: "Allow HDR10 and HLG dynamic range output; turn off to force SDR tone-mapping.",
                isOn: $viewModel.hdrEnabled
            )
            toggleSettingRow(
                title: "Match Content Frame Rate",
                subtitle: "Automatically switch display refresh rate and dynamic range criteria.",
                isOn: $viewModel.matchContentFrameRate
            )
            toggleSettingRow(
                title: "Lossless Multichannel Audio",
                subtitle: "Bridge TrueHD and DTS tracks up to 7.1 lossless LPCM/FLAC.",
                isOn: $viewModel.losslessMultichannelAudio
            )
            toggleSettingRow(
                title: "TrueHD Atmos & DTS:X",
                subtitle: "Enable spatial height and object audio rendering when supported.",
                isOn: $viewModel.objectAudioEnabled
            )
            toggleSettingRow(
                title: "Seek Cache",
                subtitle: "Keep decoded media segments cached across seeks and reopens.",
                isOn: $viewModel.seekCacheEnabled
            )

        case .subtitles:
            actionSettingRow(
                title: "Style & Preview",
                value: "\(viewModel.subtitleTextColor) · \(Int((viewModel.subtitleTextOpacity * 100).rounded()))%",
                icon: "paintpalette"
            ) {
                withAnimation(.easeOut(duration: 0.16)) { rightRoute = .subtitlesStylePreview }
                DispatchQueue.main.async { focusedRightTarget = .detailFirstControl }
            }
            .focused($focusedRightTarget, equals: .detailFirstControl)

            actionSettingRow(
                title: "Size & Position",
                value: "\(Int(viewModel.subtitleFontSize)) pt · \(viewModel.subtitleFontWeight)",
                icon: "textformat.size"
            ) {
                withAnimation(.easeOut(duration: 0.16)) { rightRoute = .subtitlesSizePosition }
                DispatchQueue.main.async { focusedRightTarget = .detailFirstControl }
            }

            actionSettingRow(
                title: "Custom Fonts",
                value: viewModel.subtitleFontName,
                icon: "character.textbox"
            ) {
                withAnimation(.easeOut(duration: 0.16)) { rightRoute = .subtitlesCustomFonts }
                DispatchQueue.main.async { focusedRightTarget = .detailFirstControl }
            }

            actionSettingRow(
                title: "First language",
                value: viewModel.displayLanguageName(for: viewModel.subtitleLanguage),
                icon: "globe"
            ) {
                withAnimation(.easeOut(duration: 0.16)) { rightRoute = .subtitlesFirstLanguage }
                DispatchQueue.main.async { focusedRightTarget = .detailFirstControl }
            }

            actionSettingRow(
                title: "Second language",
                value: viewModel.displayLanguageName(for: viewModel.secondarySubtitleLanguage),
                icon: "globe.badge.chevron.backward"
            ) {
                withAnimation(.easeOut(duration: 0.16)) { rightRoute = .subtitlesSecondLanguage }
                DispatchQueue.main.async { focusedRightTarget = .detailFirstControl }
            }

            cycleSettingRow(title: "Turn On Subtitles", value: viewModel.subtitleAutoMode) {
                viewModel.subtitleAutoMode = viewModel.nextValue(after: viewModel.subtitleAutoMode, in: SettingsViewModel.subtitleAutoOptions)
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
            toggleSettingRow(
                title: "AI Live Subtitle Translation",
                subtitle: "Translates upcoming SRT/VTT lines in batches ahead of playback (leaves ASS & PGS untouched).",
                isOn: $viewModel.aiTranslationEnabled
            )
            cycleSettingRow(title: "Translation Provider", value: viewModel.aiTranslationProvider) {
                viewModel.aiTranslationProvider = viewModel.nextValue(
                    after: viewModel.aiTranslationProvider,
                    in: SettingsViewModel.aiTranslationProviderOptions
                )
                viewModel.saveSettings(context: modelContext)
            }
            cycleSettingRow(title: "Target Language", value: viewModel.displayLanguageName(for: viewModel.aiTranslationTargetLanguage)) {
                let codes = SettingsViewModel.languageOptions.map(\.code)
                viewModel.aiTranslationTargetLanguage = viewModel.nextValue(after: viewModel.aiTranslationTargetLanguage, in: codes)
                viewModel.saveSettings(context: modelContext)
            }
            textFieldSettingRow(
                title: "Translation API Key",
                placeholder: viewModel.aiTranslationProvider == "Custom (Ollama / OpenAI)" ? "Optional for local Ollama" : "Paste your provider API key",
                text: $viewModel.aiTranslationApiKey,
                isSecure: true
            )
            if viewModel.aiTranslationProvider == "Custom (Ollama / OpenAI)" {
                textFieldSettingRow(
                    title: "Custom Endpoint URL",
                    placeholder: "http://localhost:11434/v1/chat/completions",
                    text: $viewModel.aiTranslationCustomEndpoint,
                    isSecure: false
                )
            }
            textFieldSettingRow(
                title: "Translation Model (Optional)",
                placeholder: viewModel.defaultAIModelPlaceholder(for: viewModel.aiTranslationProvider),
                text: $viewModel.aiTranslationModel,
                isSecure: false
            )

        case .skipIntroCredits:
            cycleSettingRow(title: "Skip Intro", value: viewModel.skipIntroMode) {
                viewModel.skipIntroMode = viewModel.nextValue(after: viewModel.skipIntroMode, in: SettingsViewModel.skipModeOptions)
                viewModel.saveSettings(context: modelContext)
            }
            .focused($focusedRightTarget, equals: .detailFirstControl)
            cycleSettingRow(title: "Skip Recap", value: viewModel.skipRecapMode) {
                viewModel.skipRecapMode = viewModel.nextValue(after: viewModel.skipRecapMode, in: SettingsViewModel.skipModeOptions)
                viewModel.saveSettings(context: modelContext)
            }
            cycleSettingRow(title: "End Credits Overlay", value: viewModel.skipCreditsMode) {
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
            cycleSettingRow(title: "Background Style", value: viewModel.backgroundStyle) {
                viewModel.backgroundStyle = viewModel.nextValue(after: viewModel.backgroundStyle, in: SettingsViewModel.backgroundStyleOptions)
                viewModel.saveSettings(context: modelContext)
            }
            .focused($focusedRightTarget, equals: .detailFirstControl)
            toggleSettingRow(
                title: "Auto-Play Muted Trailers on Focus",
                subtitle: "Expands focused Home cards and plays muted TMDB trailer previews after 2 seconds.",
                isOn: $viewModel.autoPlayMutedTrailers
            )
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
            toggleSettingRow(
                title: "Blur Unwatched Episode Thumbnails",
                subtitle: "Blurs Series episode thumbnails for unwatched episodes until watched or revealed.",
                isOn: $viewModel.blurUnwatchedEpisodeThumbnails
            )
            toggleSettingRow(
                title: "Hide Unwatched Episode Descriptions",
                subtitle: "Hides Series episode synopses on unwatched episodes until watched, focused, or revealed.",
                isOn: $viewModel.hideUnwatchedEpisodeDescriptions
            )
            cycleSettingRow(title: "Interface Language", value: viewModel.displayLanguageName(for: viewModel.preferredLanguage)) {
                let codes = SettingsViewModel.languageOptions.map(\.code)
                viewModel.preferredLanguage = viewModel.nextValue(after: viewModel.preferredLanguage, in: codes)
                viewModel.saveSettings(context: modelContext)
            }

        case .library:
            actionSettingRow(title: "Export Watch History (JSON)", icon: "square.and.arrow.up") {
                _ = viewModel.exportWatchHistory(context: modelContext)
            }
            .focused($focusedRightTarget, equals: .detailFirstControl)
            actionSettingRow(title: "Import Watch History (JSON)", icon: "square.and.arrow.down") {
                if let data = viewModel.exportData {
                    viewModel.importWatchHistory(data: data, context: modelContext)
                }
            }
            actionSettingRow(title: "Clear Watch History", icon: "trash") {
                viewModel.clearWatchHistory(context: modelContext)
            }
            actionSettingRow(title: "Clear Watchlist", icon: "bookmark.slash") {
                viewModel.clearWatchlist(context: modelContext)
            }

        case .serversAccounts:
            actionSettingRow(title: "Setup via Phone (QR Code)", icon: "qrcode") {
                showPhoneQRSetup = true
            }
            .focused($focusedRightTarget, equals: .detailFirstControl)
            addonManifestManagerSection
            textFieldSettingRow(
                title: "TMDB API Key (v3)",
                placeholder: "Enter TMDB v3 API Key",
                text: $viewModel.tmdbApiKey,
                isSecure: true
            )
            textFieldSettingRow(
                title: "MDBList API Key (Optional)",
                placeholder: "Enter MDBList API key (IMDb, RT, Metacritic, Letterboxd)",
                text: $viewModel.mdblistApiKey,
                isSecure: true
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

        case .trakt:
            textFieldSettingRow(
                title: "Trakt Username",
                placeholder: "Enter Trakt handle",
                text: $viewModel.traktUsername,
                isSecure: false
            )
            .focused($focusedRightTarget, equals: .detailFirstControl)
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
            .focused($focusedRightTarget, equals: .detailFirstControl)

        case .quickSetup:
            actionSettingRow(title: "Setup via Phone (QR Code)", icon: "qrcode.viewfinder") {
                showPhoneQRSetup = true
            }
            .focused($focusedRightTarget, equals: .detailFirstControl)
            addonManifestManagerSection
            actionSettingRow(
                title: "MDBList Ratings",
                value: viewModel.mdblistApiKey.isEmpty ? "Optional (Not Set)" : "Configured",
                icon: "star.bubble"
            ) {
                selectedCategory = .serversAccounts
                rightRoute = .categoryDetail
                DispatchQueue.main.async {
                    focusedRightTarget = .detailFirstControl
                }
            }
            actionSettingRow(
                title: "AI Translation Key",
                value: viewModel.aiTranslationApiKey.isEmpty ? "Optional (Not Set)" : "Configured (\(viewModel.aiTranslationProvider))",
                icon: "sparkles"
            ) {
                selectedCategory = .subtitles
                rightRoute = .categoryDetail
                DispatchQueue.main.async {
                    focusedRightTarget = .detailFirstControl
                }
            }
            Text("Phone QR Web Server starts only while the Setup via Phone screen is open and stops immediately on close.")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 4)

        case .about:
            infoRow(title: "Application", value: "AuraTV 1.0.0")
            infoRow(title: "Target Platform", value: "Apple TV 4K (tvOS 18+)")
            infoRow(title: "Media Playback", value: "AetherEngine (4K HDR10+ / Dolby Vision / TrueHD)")
            infoRow(title: "Metadata & Streams", value: "TMDB v3 • AIOStreams • Wyzie / SubDL")
        }
    }

    // MARK: - Reusable Native Row Builders (26pt Titles, 22pt Values, Reference White Focus Fill)

    private func cycleSettingRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        SettingsCycleRowButton(title: title, value: value, action: action)
    }

    private func toggleSettingRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 21))
                    .foregroundStyle(.white.opacity(0.66))
            }
        }
        .onChange(of: isOn.wrappedValue) { _, _ in
            viewModel.saveSettings(context: modelContext)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func textFieldSettingRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)

            if isSecure {
                SecureField(placeholder, text: text)
                    .font(.system(size: 21))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(16)
                    .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 12))
            } else {
                TextField(placeholder, text: text)
                    .font(.system(size: 21))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(16)
                    .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var addonManifestManagerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Stremio / AIOStreams / Nuvio Manifest URL")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 14) {
                TextField("https://.../manifest.json (use iPhone Remote keyboard)", text: $viewModel.quickManifestInput)
                    .font(.system(size: 21))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit {
                        Task {
                            await viewModel.addAndValidateManifestURL(viewModel.quickManifestInput, context: modelContext)
                        }
                    }
                    .padding(16)
                    .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 12))

                Button {
                    Task {
                        await viewModel.addAndValidateManifestURL(viewModel.quickManifestInput, context: modelContext)
                    }
                } label: {
                    Text(viewModel.isTestingConnection ? "Validating..." : "Add / Save")
                        .font(.system(size: 20, weight: .bold))
                        .modifier(SettingsPrimaryPillModifier())
                }
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()
                .disabled(viewModel.isTestingConnection)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )

        textFieldSettingRow(
            title: "AIOStreams / Stremio URLs",
            placeholder: "https://aiostreams.example.com/manifest.json",
            text: $viewModel.aioStreamsUrl,
            isSecure: false
        )

        textFieldSettingRow(
            title: "Nuvio / Addon URLs",
            placeholder: "Comma or newline separated extra manifest.json URLs",
            text: $viewModel.aioStreamsAdditionalUrls,
            isSecure: false
        )

        if !viewModel.configuredManifestURLs.isEmpty {
            ForEach(Array(viewModel.configuredManifestURLs.enumerated()), id: \.element) { idx, manifestURL in
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(idx == 0 ? "Primary Addon" : "Addon \(idx + 1)")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(idx == 0 ? Color.green : Color.white.opacity(0.62))
                        Text(manifestURL)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    Spacer()

                    if idx > 0 {
                        Button("Set Primary") {
                            viewModel.makePrimaryManifestURL(manifestURL, context: modelContext)
                        }
                        .font(.system(size: 18, weight: .semibold))
                        .modifier(SettingsFocusablePillModifier())
                        .buttonStyle(AuraButtonStyle())
                        .focusEffectDisabled()
                    }

                    Button("Remove") {
                        viewModel.removeManifestURL(manifestURL, context: modelContext)
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .modifier(SettingsFocusablePillModifier())
                    .buttonStyle(AuraButtonStyle())
                    .focusEffectDisabled()
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }

        actionSettingRow(
            title: viewModel.isTestingConnection ? "Validating Manifests..." : "Validate & Save All Addons",
            icon: "checkmark.seal"
        ) {
            viewModel.saveSettings(context: modelContext)
            Task {
                await viewModel.testAIOStreamsConnection()
            }
        }

        if let connectionStatus = viewModel.connectionTestStatus {
            Text(connectionStatus)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(connectionStatus.hasPrefix("Connected") ? Color.green : Color.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
        }
    }

    private func actionSettingRow(
        title: String,
        value: String? = nil,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        SettingsActionRowButton(title: title, value: value, icon: icon, action: action)
    }

    private var audioSyncOffsetRow: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Audio Sync Offset")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Current delay: \(viewModel.formatAudioSyncOffset(viewModel.audioSyncOffsetMs))")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.64))
            }

            Spacer()

            HStack(spacing: 12) {
                Button("-25 ms") {
                    viewModel.adjustAudioSyncOffset(by: -25)
                    viewModel.saveSettings(context: modelContext)
                }
                .font(.system(size: 19, weight: .semibold))
                .modifier(SettingsFocusablePillModifier())
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()

                Button("Reset") {
                    viewModel.audioSyncOffsetMs = 0
                    viewModel.saveSettings(context: modelContext)
                }
                .font(.system(size: 19, weight: .semibold))
                .modifier(SettingsFocusablePillModifier())
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()

                Button("+25 ms") {
                    viewModel.adjustAudioSyncOffset(by: 25)
                    viewModel.saveSettings(context: modelContext)
                }
                .font(.system(size: 19, weight: .semibold))
                .modifier(SettingsFocusablePillModifier())
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
            Spacer()
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Focus Helpers for Settings Right Panel (Reference Solid White Pill + Dark Label)

private struct SettingsCycleRowButton: View {
    let title: String
    let value: String
    let action: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isFocused ? Color.black : Color.white)
                Spacer()
                HStack(spacing: 10) {
                    Text(value)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(isFocused ? Color.black.opacity(0.75) : Color.white.opacity(0.74))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isFocused ? Color.black.opacity(0.6) : Color.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 21)
            .background(
                isFocused ? Color.white : Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 2.5 : 1)
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
    }
}

private struct SettingsActionRowButton: View {
    let title: String
    let value: String?
    let icon: String
    let action: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isFocused ? Color.black : Color.white.opacity(0.86))
                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isFocused ? Color.black : Color.white)
                Spacer()
                if let value, !value.isEmpty {
                    Text(value)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(isFocused ? Color.black.opacity(0.70) : Color.white.opacity(0.70))
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isFocused ? Color.black.opacity(0.65) : Color.white.opacity(0.45))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 21)
            .background(
                isFocused ? Color.white : Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 2.5 : 1)
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
    }
}

private struct SettingsPresetRowButton: View {
    let title: String
    let subtitle: String
    let swatchColor: Color
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Circle()
                    .fill(swatchColor)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(isFocused ? Color.black.opacity(0.3) : Color.white.opacity(0.35), lineWidth: 1.5))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(isFocused ? Color.black : Color.white)
                    Text(subtitle)
                        .font(.system(size: 20))
                        .foregroundStyle(isFocused ? Color.black.opacity(0.68) : Color.white.opacity(0.66))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(isFocused ? Color.black : Color.white)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(
                isFocused ? Color.white : Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 2.5 : 1)
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
    }
}

private struct SettingsFontRowButton: View {
    let fontName: String
    let sampleFont: Font
    let sampleColor: Color
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(fontName)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(isFocused ? Color.black : Color.white)
                    Text("تجربة الخط العربي · Sample Subtitle Text")
                        .font(sampleFont)
                        .foregroundStyle(isFocused ? Color.black.opacity(0.80) : sampleColor)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(isFocused ? Color.black : Color.white)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(
                isFocused ? Color.white : Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 2.5 : 1)
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
    }
}

private struct SettingsLanguageRowButton: View {
    let name: String
    let code: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            HStack {
                Text(name)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isFocused ? Color.black : Color.white)
                Spacer()
                Text(code)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isFocused ? Color.black.opacity(0.62) : Color.white.opacity(0.6))
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(isFocused ? Color.black : Color.white)
                        .padding(.leading, 10)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(
                isFocused ? Color.white : Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 2.5 : 1)
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
    }
}

private struct SettingsFocusableRowModifier: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .background(
                Color.white.opacity(isFocused ? 0.16 : 0.06),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 2.5 : 1)
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}

private struct SettingsFocusablePillModifier: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(isFocused ? Color.white : Color.white.opacity(0.14), in: Capsule())
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}

private struct SettingsPrimaryPillModifier: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.black)
            .padding(.horizontal, 26)
            .padding(.vertical, 12)
            .background(Color.white, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(isFocused ? Color.white : .clear, lineWidth: 2.5)
                    .padding(-4)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}
