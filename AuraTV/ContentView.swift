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
                NavigationStack {
                    MovieDetailView(tmdbId: 37724)
                }
            case .playerHUD:
                PlayerPreviewHostView()
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
            case .standard(let tab): activeMode = tab.rawValue
            }
            Self.logger.notice("ContentView active tab: \(activeMode, privacy: .public)")
            print("[AuraTV] ContentView active tab: \(activeMode)")
        }
    }
}

private struct PlayerPreviewHostView: View {
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
                playerViewModel.configurePreviewHUD()
                isReady = true
            }
        }
    }
}
