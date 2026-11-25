import SwiftUI
import SwiftData
import os

@main
struct AuraTVApp: App {
    private static let logger = Logger(subsystem: "com.auratv.AuraTV", category: "App")

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            WatchHistory.self,
            WatchlistItem.self,
            AppSettings.self,
            CustomArtwork.self
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

        do {
            let all = try context.fetch(descriptor)
            if let settings = all.first {
                // Existing row: use persisted key only if the user has set one;
                // otherwise fall back to the built-in default already on TMDBService.
                if !settings.tmdbApiKey.isEmpty {
                    TMDBService.shared.apiKey = settings.tmdbApiKey
                }
                // Always keep the row's key in sync with the service default
                // so Settings shows the correct value.
                if settings.tmdbApiKey.isEmpty {
                    settings.tmdbApiKey = TMDBService.shared.apiKey
                    try? context.save()
                }
                AIOStreamsService.shared.manifestURL = settings.aioStreamsUrl
                SubtitleService.shared.subdlApiKey = settings.subdlApiKey
                SubtitleService.shared.openSubtitlesApiKey = settings.openSubtitlesApiKey
                Self.logger.notice("Loaded existing AppSettings (TMDB key present: \(!TMDBService.shared.apiKey.isEmpty))")
            } else {
                // First launch – no AppSettings row yet.
                // Insert one carrying the built-in default key so Settings shows it.
                let defaults = AppSettings()
                // AppSettings.init() already sets tmdbApiKey = default key.
                context.insert(defaults)
                try? context.save()
                // TMDBService.shared.apiKey already equals the default; nothing to override.
                Self.logger.notice("First launch - inserted default AppSettings")
                print("[AuraTV] First launch – inserted default AppSettings (TMDB key: \(TMDBService.shared.apiKey.prefix(8))...)")
            }
        } catch {
            Self.logger.error("Failed to load AppSettings: \(error.localizedDescription, privacy: .public)")
            print("[AuraTV] Failed to load AppSettings: \(error)")
        }
    }
}
