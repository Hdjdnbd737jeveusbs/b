import Foundation

// MARK: - Generic Response

struct TMDBResponse<T: Codable>: Codable {
    let page: Int
    let results: [T]
    let totalPages: Int
    let totalResults: Int
}

// MARK: - Movie

struct TMDBMovie: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let voteAverage: Double?
    let genreIds: [Int]?
    let adult: Bool?
    let popularity: Double?
}

struct TMDBMovieDetail: Codable, Identifiable {
    let id: Int
    let title: String
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let voteAverage: Double?
    let runtime: Int?
    let genres: [TMDBGenre]?
    let productionCountries: [TMDBCountry]?
    let spokenLanguages: [TMDBLanguage]?
    let status: String?
    let tagline: String?
    let budget: Int?
    let revenue: Int?
    let credits: TMDBCredits?
    let releaseDates: TMDBReleaseDatesResponse?
}

// MARK: - Series

struct TMDBSeries: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let genreIds: [Int]?
    let popularity: Double?
    let originCountry: [String]?
}

struct TMDBSeriesDetail: Codable, Identifiable {
    let id: Int
    let name: String
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let genres: [TMDBGenre]?
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let seasons: [TMDBSeason]?
    let status: String?
    let tagline: String?
    let episodeRunTime: [Int]?
    let credits: TMDBCredits?
    let contentRatings: TMDBContentRatingsResponse?
}

// MARK: - Shared Types

struct TMDBGenre: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct TMDBCastMember: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
    let order: Int?
}

struct TMDBCredits: Codable, Hashable {
    let cast: [TMDBCastMember]?
}

struct TMDBSeason: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let seasonNumber: Int
    let episodeCount: Int?
    let posterPath: String?
    let overview: String?
    let airDate: String?
}

struct TMDBEpisode: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let overview: String?
    let episodeNumber: Int
    let seasonNumber: Int
    let stillPath: String?
    let airDate: String?
    let voteAverage: Double?
    let runtime: Int?
}

struct TMDBSeasonDetail: Codable {
    let episodes: [TMDBEpisode]?
}

// MARK: - Metadata Types

struct TMDBCountry: Codable, Hashable {
    let iso31661: String?
    let name: String?
}

struct TMDBLanguage: Codable, Hashable {
    let iso6391: String?
    let englishName: String?
    let name: String?
}

// MARK: - Release Dates / Content Ratings

struct TMDBReleaseDatesResponse: Codable {
    let results: [TMDBReleaseDateCountry]?
}

struct TMDBReleaseDateCountry: Codable {
    let iso31661: String?
    let releaseDates: [TMDBReleaseDate]?
}

struct TMDBReleaseDate: Codable {
    let certification: String?
    let type: Int?
}

struct TMDBContentRatingsResponse: Codable {
    let results: [TMDBContentRating]?
}

struct TMDBContentRating: Codable {
    let iso31661: String?
    let rating: String?
}

// MARK: - Multi-Search

struct TMDBSearchResponse: Codable {
    let page: Int
    let results: [TMDBSearchResult]
    let totalPages: Int
    let totalResults: Int
}

struct TMDBSearchResult: Codable, Identifiable, Hashable {
    let id: Int
    let mediaType: String?
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let genreIds: [Int]?

    var displayTitle: String { title ?? name ?? "Unknown" }
    var displayDate: String { releaseDate ?? firstAirDate ?? "" }
    var isMovie: Bool { mediaType == "movie" }
}

// MARK: - External IDs

struct TMDBExternalIds: Codable {
    let imdbId: String?
    let freebaseMid: String?
    let freebaseId: String?
    let tvdbId: Int?
    let tvrageId: Int?
    let facebookId: String?
    let instagramId: String?
    let twitterId: String?
}

// MARK: - Genre ID Dictionaries

struct TMDBGenres {
    static let movie: [Int: String] = [
        28: "Action",
        12: "Adventure",
        16: "Animation",
        35: "Comedy",
        80: "Crime",
        99: "Documentary",
        18: "Drama",
        10751: "Family",
        14: "Fantasy",
        36: "History",
        27: "Horror",
        10402: "Music",
        9648: "Mystery",
        10749: "Romance",
        878: "Sci-Fi",
        10770: "TV Movie",
        53: "Thriller",
        10752: "War",
        37: "Western"
    ]

    static let tv: [Int: String] = [
        10759: "Action & Adventure",
        16: "Animation",
        35: "Comedy",
        80: "Crime",
        99: "Documentary",
        18: "Drama",
        10751: "Family",
        10762: "Kids",
        9648: "Mystery",
        10763: "News",
        10764: "Reality",
        10765: "Sci-Fi & Fantasy",
        10766: "Soap",
        10767: "Talk",
        10768: "War & Politics",
        37: "Western"
    ]

    /// Resolve genre IDs to names for a movie.
    static func movieGenreNames(for ids: [Int]?) -> [String] {
        guard let ids else { return [] }
        return ids.compactMap { movie[$0] }
    }

    /// Resolve genre IDs to names for a TV series.
    static func tvGenreNames(for ids: [Int]?) -> [String] {
        guard let ids else { return [] }
        return ids.compactMap { tv[$0] }
    }
}
