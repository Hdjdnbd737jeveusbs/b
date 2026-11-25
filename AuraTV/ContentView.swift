import SwiftUI
import SwiftData
import os

// MARK: - Content View (Native Glass Sidebar Navigation)

struct ContentView: View {
    private static let logger = Logger(subsystem: "com.auratv.AuraTV", category: "Navigation")

    /// Reads `-screenshotTab <name>` from launch arguments (or NSArgumentDomain)
    /// so CI screenshot automation can open directly onto any tab.
    private static func initialTabFromArguments() -> AppTab {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-screenshotTab"),
           args.indices.contains(idx + 1),
           let tab = AppTab(rawValue: args[idx + 1].capitalized) {
            return tab
        }
        if let udTab = UserDefaults.standard.string(forKey: "screenshotTab"),
           let tab = AppTab(rawValue: udTab.capitalized) {
            return tab
        }
        return .home
    }

    @State private var selectedTab: AppTab = ContentView.initialTabFromArguments()

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
        .onAppear {
            let requested = Self.initialTabFromArguments()
            if selectedTab != requested {
                selectedTab = requested
            }
            let activeTab = selectedTab.rawValue
            Self.logger.notice("ContentView active tab: \(activeTab, privacy: .public)")
            print("[AuraTV] ContentView active tab: \(activeTab)")
        }
    }
}
