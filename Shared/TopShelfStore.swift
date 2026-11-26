import Foundation
#if canImport(TVServices)
import TVServices
#endif

// MARK: - Shared Top Shelf Store (Main App <-> AuraTVTopShelf.appex)

struct TopShelfEntry: Codable, Equatable, Sendable {
    let tmdbId: Int
    let mediaType: String // "movie" or "series"
    let title: String
    let subtitle: String?
    let imagePath: String?
    let isContinueWatching: Bool
}

struct TopShelfSnapshot: Codable, Sendable {
    let tmdbApiKey: String
    let updatedAt: Date
    let continueWatching: [TopShelfEntry]
    let featured: [TopShelfEntry]
}

enum TopShelfSharedStore {
    static let appGroupIdentifier = "group.com.auratv.AuraTV"
    private static let fileName = "auratv_topshelf_snapshot.json"
    private static let defaultsKey = "auratv.topshelf.snapshot"

    static func save(_ snapshot: TopShelfSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let fileURL = containerURL.appendingPathComponent(fileName)
            try? data.write(to: fileURL, options: .atomic)
        }

        if let suite = UserDefaults(suiteName: appGroupIdentifier) {
            suite.set(data, forKey: defaultsKey)
        }
        UserDefaults.standard.set(data, forKey: defaultsKey)

        #if canImport(TVServices)
        TVTopShelfContentProvider.topShelfContentDidChange()
        #endif
    }

    static func load() -> TopShelfSnapshot? {
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let fileURL = containerURL.appendingPathComponent(fileName)
            if let data = try? Data(contentsOf: fileURL),
               let decoded = try? JSONDecoder().decode(TopShelfSnapshot.self, from: data) {
                return decoded
            }
        }

        if let suite = UserDefaults(suiteName: appGroupIdentifier),
           let data = suite.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(TopShelfSnapshot.self, from: data) {
            return decoded
        }

        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(TopShelfSnapshot.self, from: data) {
            return decoded
        }

        return nil
    }
}
