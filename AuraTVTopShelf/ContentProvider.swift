import Foundation
import TVServices

// MARK: - Top Shelf Content Provider Extension (AuraTVTopShelf.appex)

final class ContentProvider: TVTopShelfContentProvider {
    private static let defaultTMDBKey = "d767cb12181edaa01840442c704329be"

    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        let snapshot = TopShelfSharedStore.load()
        let continueEntries = snapshot?.continueWatching ?? []
        let featuredEntries = snapshot?.featured ?? []

        if !featuredEntries.isEmpty || !continueEntries.isEmpty {
            completionHandler(Self.buildContent(continueEntries: continueEntries, featuredEntries: featuredEntries))
            return
        }

        let apiKey = (snapshot?.tmdbApiKey.isEmpty == false ? snapshot?.tmdbApiKey : nil) ?? Self.defaultTMDBKey
        Self.fetchTrendingFallback(apiKey: apiKey) { fetched in
            let content = Self.buildContent(continueEntries: continueEntries, featuredEntries: fetched)
            completionHandler(content)
        }
    }

    private static func buildContent(
        continueEntries: [TopShelfEntry],
        featuredEntries: [TopShelfEntry]
    ) -> TVTopShelfContent? {
        var sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = []

        if !continueEntries.isEmpty {
            let cwItems = continueEntries.prefix(10).map { makeSectionedItem(from: $0, preferBackdrop: true) }
            let cwCollection = TVTopShelfItemCollection(items: cwItems)
            cwCollection.title = "Continue Watching"
            sections.append(cwCollection)
        }

        if !featuredEntries.isEmpty {
            let featuredItems = featuredEntries.prefix(12).map { makeSectionedItem(from: $0, preferBackdrop: false) }
            let featuredCollection = TVTopShelfItemCollection(items: featuredItems)
            featuredCollection.title = "Featured on AuraTV"
            sections.append(featuredCollection)
        }

        guard !sections.isEmpty else { return nil }
        return TVTopShelfSectionedContent(sections: sections)
    }

    private static func makeSectionedItem(from entry: TopShelfEntry, preferBackdrop: Bool) -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: "\(entry.mediaType)-\(entry.tmdbId)")
        item.title = entry.subtitle.map { "\(entry.title) · \($0)" } ?? entry.title
        item.imageShape = preferBackdrop ? .hdtv : .poster

        if let rawPath = entry.imagePath, !rawPath.isEmpty {
            let size1x = preferBackdrop ? "w780" : "w342"
            let size2x = preferBackdrop ? "w1280" : "w500"
            if let url1x = tmdbImageURL(path: rawPath, size: size1x) {
                item.setImageURL(url1x, for: .screenScale1x)
            }
            if let url2x = tmdbImageURL(path: rawPath, size: size2x) {
                item.setImageURL(url2x, for: .screenScale2x)
            }
        }

        if let detailURL = URL(string: "auratv://detail?type=\(entry.mediaType)&id=\(entry.tmdbId)") {
            item.displayAction = TVTopShelfAction(url: detailURL)
            item.playAction = TVTopShelfAction(url: detailURL)
        }

        return item
    }

    private static func tmdbImageURL(path: String, size: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    private static func fetchTrendingFallback(
        apiKey: String,
        completion: @escaping ([TopShelfEntry]) -> Void
    ) {
        guard let encoded = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.themoviedb.org/3/trending/movie/day?api_key=\(encoded)") else {
            completion([])
            return
        }

        struct Response: Decodable {
            struct Item: Decodable {
                let id: Int
                let title: String
                let poster_path: String?
            }
            let results: [Item]
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
                completion([])
                return
            }
            let entries = decoded.results.prefix(10).map {
                TopShelfEntry(
                    tmdbId: $0.id,
                    mediaType: "movie",
                    title: $0.title,
                    subtitle: nil,
                    imagePath: $0.poster_path,
                    isContinueWatching: false
                )
            }
            completion(entries)
        }.resume()
    }
}
