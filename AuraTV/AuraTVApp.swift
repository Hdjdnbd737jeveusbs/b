import SwiftUI
import SwiftData

@main
struct AuraTVApp: App {

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            WatchHistory.self,
            WatchlistItem.self,
            AppSettings.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // Load API key from persisted settings into the shared service.
        loadAPIKeyFromSettings()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: - Helpers

    private func loadAPIKeyFromSettings() {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? context.fetch(descriptor).first {
            TMDBService.shared.apiKey = settings.tmdbApiKey
            AIOStreamsService.shared.manifestURL = settings.aioStreamsUrl
            SubtitleService.shared.subdlApiKey = settings.subdlApiKey
            SubtitleService.shared.openSubtitlesApiKey = settings.openSubtitlesApiKey
        }
    }
}
