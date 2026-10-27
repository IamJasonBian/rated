import Foundation

// Port of build/src/lib/tmdb.js. Movie data comes from the backend's /tmdb/*
// proxy (key stays server-side); any failure falls back to the Mock catalog.
// Every movie that flows through is indexed so `find(id:)` can resolve ids
// from feed items, rankings and reviews synchronously.

private struct TMDBGenre: Decodable { var id: Int; var name: String }
private struct TMDBPerson: Decodable { var name: String; var character: String?; var job: String?; var profile_path: String? }
private struct TMDBCredits: Decodable { var cast: [TMDBPerson]?; var crew: [TMDBPerson]? }
private struct TMDBVideo: Decodable { var key: String; var name: String; var site: String; var type: String }
private struct TMDBVideos: Decodable { var results: [TMDBVideo] }

private struct TMDBMovie: Decodable {
    var id: Int
    var title: String?
    var original_title: String?
    var original_language: String?
    var release_date: String?
    var overview: String?
    var poster_path: String?
    var backdrop_path: String?
    var genre_ids: [Int]?
    var genres: [TMDBGenre]?
    var runtime: Int?
    var vote_average: Double?
    var vote_count: Int?
    var credits: TMDBCredits?
    var videos: TMDBVideos?
}

private struct TMDBPage: Decodable { var results: [TMDBMovie] }

@MainActor
final class Catalog {
    static let shared = Catalog()

    static let genreNames: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy",
        80: "Crime", 99: "Documentary", 18: "Drama", 10751: "Family",
        14: "Fantasy", 36: "History", 27: "Horror", 10402: "Music",
        9648: "Mystery", 10749: "Romance", 878: "Sci-Fi",
        10770: "TV Movie", 53: "Thriller", 10752: "War", 37: "Western",
    ]

    private var index: [String: Movie] = [:]
    private var listCache: [String: (movies: [Movie], expires: Date)] = [:]
    private let listTTL: TimeInterval = 10 * 60

    private init() {
        for m in Mock.movies + Mock.upcoming { index[m.id] = m }
    }

    func register(_ movies: [Movie]) {
        for m in movies where index[m.id] == nil || m.tmdbId != nil { index[m.id] = m }
    }

    /// Synchronous lookup; never nil when an id or title is known (stub fallback),
    /// so navigation always has something to open and enrich.
    func find(_ id: String?, title: String? = nil) -> Movie? {
        if let id, let hit = index[id] { return hit }
        if let title, let hit = index.values.first(where: { $0.title == title }) { return hit }
        guard id != nil || title != nil else { return nil }
        let tmdbId = id.flatMap { $0.hasPrefix("tmdb-") ? Int($0.dropFirst(5)) : nil }
        return Movie(id: id ?? "stub-\(UUID().uuidString)", tmdbId: tmdbId, title: title ?? "Unknown")
    }

    private static func map(_ t: TMDBMovie) -> Movie {
        let img = Mock.tmdbImg
        let genres = (t.genres?.map(\.name) ?? (t.genre_ids ?? []).compactMap { genreNames[$0] })
            .map { $0 == "Science Fiction" ? "Sci-Fi" : $0 }
        let trailers = (t.videos?.results ?? [])
            .filter { $0.site == "YouTube" && ($0.type == "Trailer" || $0.type == "Teaser") }
            .enumerated().map { Trailer(title: $1.name, videoKey: $1.key, isPrimary: $0 == 0) }
        return Movie(
            id: "tmdb-\(t.id)", tmdbId: t.id, title: t.title ?? "Untitled",
            originalTitle: t.original_title,
            releaseYear: t.release_date.flatMap { Int($0.prefix(4)) },
            releaseDate: t.release_date, runtimeMinutes: t.runtime,
            synopsis: t.overview ?? "",
            originalLanguage: t.original_language,
            isInternational: (t.original_language ?? "en") != "en",
            posterURL: t.poster_path.map { "\(img)/w500\($0)" },
            backdropURL: t.backdrop_path.map { "\(img)/w1280\($0)" },
            genres: genres,
            directors: (t.credits?.crew ?? []).filter { $0.job == "Director" }.map(\.name),
            cast: (t.credits?.cast ?? []).prefix(10).map { CastMember(name: $0.name, character: $0.character, profileURL: $0.profile_path.map { "\(img)/w185\($0)" }) },
            trailers: trailers,
            avgUserRating: t.vote_average.map { ($0 * 10).rounded() / 10 },
            userRatingCount: t.vote_count ?? 0
        )
    }

    private func list(_ path: String) async -> [Movie]? {
        if let c = listCache[path], c.expires > .now { return c.movies }
        guard let data = await APIClient.shared.raw(path),
              let page = try? JSONDecoder().decode(TMDBPage.self, from: data) else { return nil }
        let movies = page.results.map(Self.map)
        register(movies)
        listCache[path] = (movies, .now.addingTimeInterval(listTTL))
        return movies
    }

    func invalidate() { listCache.removeAll() }

    func popular() async -> [Movie] {
        guard var ms = await list("/tmdb/popular"), !ms.isEmpty else { return Mock.movies }
        for i in ms.indices { ms[i].trendingRank = i + 1 }
        return ms
    }

    func upcoming() async -> [Movie] {
        guard let ms = await list("/tmdb/upcoming"), !ms.isEmpty else { return Mock.upcoming }
        let future = ms.filter { ($0.daysUntilRelease ?? -1) > 0 }
        return future.isEmpty ? Mock.upcoming : future
    }

    func topRated() async -> [Movie]? {
        guard var ms = await list("/tmdb/top-rated") else { return nil }
        for i in ms.indices { ms[i].globalRank = i + 1 }
        return ms
    }

    /// TMDB search with a local title filter as the offline fallback.
    func search(_ q: String) async -> [Movie] {
        guard q.count >= 2 else { return [] }
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        if let ms = await list("/tmdb/search?q=\(enc)&page=1") { return ms }
        let needle = q.lowercased()
        return (Mock.movies + Mock.upcoming).filter {
            $0.title.lowercased().contains(needle) || $0.directors.contains { $0.lowercased().contains(needle) }
        }
    }

    /// Full detail (cast, trailers, backdrop). Keeps the original id so
    /// saved/watchlist membership still matches.
    func detail(_ movie: Movie) async -> Movie {
        guard let tid = movie.tmdbId,
              let data = await APIClient.shared.raw("/tmdb/movie/\(tid)"),
              let t = try? JSONDecoder().decode(TMDBMovie.self, from: data) else { return movie }
        var full = Self.map(t)
        full.id = movie.id
        full.posterURL = full.posterURL ?? movie.posterURL
        full.backdropURL = full.backdropURL ?? movie.backdropURL
        full.trendingRank = movie.trendingRank
        full.globalRank = movie.globalRank
        index[full.id] = full
        return full
    }
}
