import Foundation

// Port of build/src/lib/tmdb.js. Movie data comes from the backend's /tmdb/*
// proxy (key stays server-side) and falls back to the backend's own /movies
// catalog when no TMDB key is configured. Every movie that flows through is
// indexed so `find(id:)` can resolve ids from rankings and reviews synchronously.

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

    private init() {}

    private static let tmdbImg = "https://image.tmdb.org/t/p"

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
        let img = tmdbImg
        let genres = (t.genres?.map(\.name) ?? (t.genre_ids ?? []).compactMap { genreNames[$0] })
            .map { $0 == "Science Fiction" ? "Sci-Fi" : $0 }
        let trailers = (t.videos?.results ?? [])
            .filter { $0.site == "YouTube" && ($0.type == "Trailer" || $0.type == "Teaser") }
            .enumerated().map { Trailer(title: $1.name, videoKey: $1.key, isPrimary: $0 == 0) }
        return Movie(
            id: "tmdb-\(t.id)", tmdbId: t.id, title: t.title ?? "Untitled",
            originalTitle: t.original_title,
            releaseYear: t.release_date.flatMap { Int($0.prefix(4)) },
            runtimeMinutes: t.runtime,
            synopsis: t.overview ?? "",
            originalLanguage: t.original_language,
            isInternational: (t.original_language ?? "en") != "en",
            posterURL: t.poster_path.map { "\(img)/w500\($0)" },
            backdropURL: t.backdrop_path.map { "\(img)/w1280\($0)" },
            genres: genres,
            directors: (t.credits?.crew ?? []).filter { $0.job == "Director" }.map(\.name),
            cast: (t.credits?.cast ?? []).prefix(10).map { CastMember(name: $0.name, character: $0.character, profileURL: $0.profile_path.map { "\(img)/w185\($0)" }) },
            trailers: trailers,
            avgUserRating: t.vote_average.map { ($0 * 10).rounded() / 10 }
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

    /// Popular films, from TMDB when configured, else the backend's own catalog.
    func popular() async -> [Movie] {
        if var ms = await list("/tmdb/popular"), !ms.isEmpty {
            for i in ms.indices { ms[i].trendingRank = i + 1 }
            return ms
        }
        return await backendMovies() ?? []
    }

    private func backendMovies(q: String? = nil) async -> [Movie]? {
        guard let rows = await APIClient.shared.movies(q: q) else { return nil }
        let ms = rows.map(Self.movie)
        register(ms)
        return ms
    }

    /// A `movies`-table row, shaped as a catalog Movie.
    static func movie(_ r: APIMovieRef) -> Movie {
        Movie(id: r.movie_id, tmdbId: r.movie_id.hasPrefix("tmdb-") ? Int(r.movie_id.dropFirst(5)) : nil, title: r.title ?? "Untitled",
              releaseYear: r.year, posterURL: r.poster_url, genres: r.genre.map { [$0] } ?? [])
    }

    /// Backfill titles/posters for ids missing from the index (saved/reviewed films from an earlier session).
    func resolveUnknown(_ ids: [String]) async {
        for id in Set(ids) where index[id] == nil {
            if let r = await APIClient.shared.movie(id) { register([Self.movie(r)]) }
        }
    }

    /// Personalized "For you" picks with who loved them; empty for cold-start
    /// users (the backend's popular fallback already shows as Highlights).
    func forYou(_ uid: String) async -> [(movie: Movie, because: [String])] {
        guard let rows = await APIClient.shared.recommendations(uid) else { return [] }
        return rows.filter { $0.reason == "similar_taste" }.map { r in
            let known = find(r.movie.movie_id)
            let m = known?.posterURL != nil ? known! : Self.movie(r.movie)
            register([m])
            return (m, r.because)
        }
    }

    /// Community top list (GET /movies/top); nil when the backend is unreachable.
    func topRated() async -> [Movie]? {
        guard let rows = await APIClient.shared.topMovies() else { return nil }
        let ms = rows.map { row in
            var m = Self.movie(row.movie)
            m.avgUserRating = row.avg_score
            return m
        }
        register(ms)
        return ms
    }

    /// Movie search: TMDB when configured, else the backend catalog. nil when the backend is unreachable.
    func search(_ q: String) async -> [Movie]? {
        guard q.count >= 2 else { return [] }
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        if let ms = await list("/tmdb/search?q=\(enc)&page=1") { return ms }
        return await backendMovies(q: q)
    }

    /// Full detail (cast, trailers, backdrop). Keeps the original id so
    /// saved membership still matches.
    func detail(_ movie: Movie) async -> Movie {
        guard let tid = movie.tmdbId,
              let data = await APIClient.shared.raw("/tmdb/movie/\(tid)"),
              let t = try? JSONDecoder().decode(TMDBMovie.self, from: data) else { return movie }
        var full = Self.map(t)
        full.id = movie.id
        full.posterURL = full.posterURL ?? movie.posterURL
        full.backdropURL = full.backdropURL ?? movie.backdropURL
        full.trendingRank = movie.trendingRank
        index[full.id] = full
        return full
    }
}
