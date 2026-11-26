import SwiftUI
import SwiftData
import os

// MARK: - Content View (Native Glass Sidebar Navigation)

struct ContentView: View {
    private static let logger = Logger(subsystem: "com.auratv.AuraTV", category: "Navigation")

    private enum ScreenshotLaunchMode {
        case standard(AppTab)
        case movieDetail
        case playerHUD
        case subtitlesMenu
        case subtitleSync
        case playbackLoading
        case changeArtwork
    }

    /// Reads `-screenshotTab <name>` from launch arguments (or NSArgumentDomain)
    /// so CI screenshot automation can open directly onto any tab or preview screen.
    private static func screenshotLaunchModeFromArguments() -> ScreenshotLaunchMode {
        let args = ProcessInfo.processInfo.arguments
        let rawArg: String?
        if let idx = args.firstIndex(of: "-screenshotTab"), args.indices.contains(idx + 1) {
            rawArg = args[idx + 1]
        } else {
            rawArg = UserDefaults.standard.string(forKey: "screenshotTab")
        }

        guard let value = rawArg?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return .standard(.home)
        }

        switch value.lowercased() {
        case "moviedetail":
            return .movieDetail
        case "playerhud":
            return .playerHUD
        case "subtitlesmenu":
            return .subtitlesMenu
        case "subtitlesync":
            return .subtitleSync
        case "playbackloading":
            return .playbackLoading
        case "changeartwork":
            return .changeArtwork
        default:
            if let tab = AppTab.allCases.first(where: { $0.rawValue.lowercased() == value.lowercased() }) {
                return .standard(tab)
            }
            return .standard(.home)
        }
    }

    private static func initialTabFromArguments() -> AppTab {
        if case .standard(let tab) = screenshotLaunchModeFromArguments() {
            return tab
        }
        return .home
    }

    @State private var selectedTab: AppTab = ContentView.initialTabFromArguments()
    @State private var launchMode: ScreenshotLaunchMode = ContentView.screenshotLaunchModeFromArguments()
    @State private var deepLinkDestination: DeepLinkDestination?

    private struct DeepLinkDestination: Identifiable, Hashable {
        let mediaType: String
        let tmdbId: Int
        var id: String { "\(mediaType)-\(tmdbId)" }
    }

    enum AppTab: String, Hashable, CaseIterable {
        case search = "Search"
        case home = "Home"
        case series = "Series"
        case movies = "Movies"
        case collections = "Collections"
        case settings = "Settings"

        var iconName: String {
            switch self {
            case .search: return "magnifyingglass"
            case .home: return "house.fill"
            case .series: return "tv"
            case .movies: return "film"
            case .collections: return "square.stack"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        Group {
            switch launchMode {
            case .movieDetail:
                MovieDetailPreviewHostView()
            case .playerHUD:
                PlayerPreviewHostView(previewMode: .hud)
            case .subtitlesMenu:
                PlayerPreviewHostView(previewMode: .subtitlesMenu)
            case .subtitleSync:
                PlayerPreviewHostView(previewMode: .subtitleSync)
            case .playbackLoading:
                PlayerPreviewHostView(previewMode: .loading)
            case .changeArtwork:
                NavigationStack {
                    ChangeArtworkView(
                        tmdbId: 37724,
                        mediaType: "movie",
                        title: "Skyfall",
                        defaultPosterPath: "/d0IVecFQvsGdSbnMAHqiYsNYaJT.jpg",
                        defaultBackdropPath: "/wkA622CCN2X0uwpgqYEOnUYEDf5.jpg",
                        defaultLogoPath: "/3FJMB018u5gvnDl7dv0IMVSWym9.png"
                    )
                }
            case .standard:
                TabView(selection: $selectedTab) {
                    // Search Tab
                    NavigationStack {
                        SearchView()
                    }
                    .tabItem {
                        Label(AppTab.search.rawValue, systemImage: AppTab.search.iconName)
                    }
                    .tag(AppTab.search)

                    // Home Tab
                    NavigationStack {
                        HomeView()
                    }
                    .tabItem {
                        Label(AppTab.home.rawValue, systemImage: AppTab.home.iconName)
                    }
                    .tag(AppTab.home)

                    // Series Tab
                    NavigationStack {
                        SeriesView()
                    }
                    .tabItem {
                        Label(AppTab.series.rawValue, systemImage: AppTab.series.iconName)
                    }
                    .tag(AppTab.series)

                    // Movies Tab
                    NavigationStack {
                        MoviesView()
                    }
                    .tabItem {
                        Label(AppTab.movies.rawValue, systemImage: AppTab.movies.iconName)
                    }
                    .tag(AppTab.movies)

                    // Collections Tab
                    NavigationStack {
                        CollectionsView()
                    }
                    .tabItem {
                        Label(AppTab.collections.rawValue, systemImage: AppTab.collections.iconName)
                    }
                    .tag(AppTab.collections)

                    // Settings Tab
                    NavigationStack {
                        SettingsView()
                    }
                    .tabItem {
                        Label(AppTab.settings.rawValue, systemImage: AppTab.settings.iconName)
                    }
                    .tag(AppTab.settings)
                }
                .tabViewStyle(.sidebarAdaptable)
            }
        }
        .onAppear {
            launchMode = Self.screenshotLaunchModeFromArguments()
            if case .standard(let requested) = launchMode, selectedTab != requested {
                selectedTab = requested
            }
            let activeMode: String
            switch launchMode {
            case .movieDetail: activeMode = "MovieDetail"
            case .playerHUD: activeMode = "PlayerHUD"
            case .subtitlesMenu: activeMode = "SubtitlesMenu"
            case .subtitleSync: activeMode = "SubtitleSync"
            case .playbackLoading: activeMode = "PlaybackLoading"
            case .changeArtwork: activeMode = "ChangeArtwork"
            case .standard(let tab): activeMode = tab.rawValue
            }
            Self.logger.notice("ContentView active tab: \(activeMode, privacy: .public)")
            print("[AuraTV] ContentView active tab: \(activeMode)")
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab != .home {
                AppThemeCoordinator.shared.clearHomePreview()
            }
        }
        .onOpenURL { url in
            guard let destination = Self.parseDeepLink(url) else { return }
            Self.logger.notice("Opening Top Shelf deep link: \(destination.mediaType, privacy: .public) id=\(destination.tmdbId)")
            if case .standard = launchMode {
                selectedTab = .home
            }
            deepLinkDestination = destination
        }
        .sheet(item: $deepLinkDestination) { dest in
            NavigationStack {
                if dest.mediaType == "series" {
                    SeriesDetailView(tmdbId: dest.tmdbId)
                } else {
                    MovieDetailView(tmdbId: dest.tmdbId)
                }
            }
        }
    }

    private static func parseDeepLink(_ url: URL) -> DeepLinkDestination? {
        guard url.scheme?.lowercased() == "auratv" else { return nil }
        let host = url.host?.lowercased() ?? ""

        if host == "detail",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            let typeVal = queryItems.first(where: { $0.name == "type" })?.value?.lowercased() ?? "movie"
            if let rawId = queryItems.first(where: { $0.name == "id" })?.value,
               let tmdbId = Int(rawId), tmdbId > 0 {
                let normalizedType = (typeVal == "series" || typeVal == "tv") ? "series" : "movie"
                return DeepLinkDestination(mediaType: normalizedType, tmdbId: tmdbId)
            }
        }

        if (host == "movie" || host == "series" || host == "tv"),
           let idSegment = url.pathComponents.first(where: { Int($0) != nil }),
           let tmdbId = Int(idSegment), tmdbId > 0 {
            let normalizedType = (host == "series" || host == "tv") ? "series" : "movie"
            return DeepLinkDestination(mediaType: normalizedType, tmdbId: tmdbId)
        }

        return nil
    }
}

private struct MovieDetailPreviewHostView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var seeded = false

    var body: some View {
        NavigationStack {
            if seeded {
                MovieDetailView(tmdbId: 37724)
            }
        }
        .onAppear {
            if !seeded {
                let descriptor = FetchDescriptor<WatchHistory>(
                    predicate: #Predicate<WatchHistory> { item in
                        item.tmdbId == 37724 && item.mediaType == "movie"
                    }
                )
                if (try? modelContext.fetch(descriptor).first) == nil {
                    let demoProgress = WatchHistory(
                        tmdbId: 37724,
                        mediaType: "movie",
                        title: "Skyfall",
                        backdropPath: "/wkA622CCN2X0uwpgqYEOnUYEDf5.jpg",
                        currentTime: 2400,
                        totalDuration: 8580,
                        lastWatched: Date(),
                        isCompleted: false
                    )
                    modelContext.insert(demoProgress)
                    try? modelContext.save()
                }
                seeded = true
            }
        }
    }
}

private struct PlayerPreviewHostView: View {
    let previewMode: PlayerViewModel.PreviewScreenMode
    @State private var playerViewModel = PlayerViewModel()
    @State private var isReady = false

    var body: some View {
        ZStack {
            Color.auraBackground.ignoresSafeArea()
            if isReady {
                PlayerView(viewModel: playerViewModel)
            }
        }
        .onAppear {
            if !isReady {
                playerViewModel.configurePreviewHUD(mode: previewMode)
                isReady = true
            }
        }
    }
}
