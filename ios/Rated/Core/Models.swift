import Foundation

struct CastMember: Codable, Hashable {
    var name: String
    var character: String?
    var profileURL: String?
}

struct Trailer: Codable, Hashable {
    var title: String
    var videoKey: String
    var isPrimary: Bool
}

// One movie shape, mirroring the web's movie objects (tmdb.js mapTmdbMovie).
// Equality is by id so sets/selection stay stable
// when a stub is later enriched with TMDB detail.
struct Movie: Identifiable, Codable {
    var id: String
    var tmdbId: Int?
    var title: String
    var originalTitle: String?
    var releaseYear: Int?
    var runtimeMinutes: Int?
    var synopsis: String = ""
    var originalLanguage: String?
    var isInternational: Bool = false
    var posterURL: String?
    var backdropURL: String?
    var genres: [String] = []
    var directors: [String] = []
    var cast: [CastMember] = []
    var trailers: [Trailer] = []
    var avgUserRating: Double?
    var trendingRank: Int?

    var primaryTrailer: Trailer? { trailers.first(where: \.isPrimary) ?? trailers.first }

    var runtimeLabel: String? {
        guard let m = runtimeMinutes, m > 0 else { return nil }
        return "\(m / 60)h \(m % 60)m"
    }
}

extension Movie: Hashable {
    static func == (a: Movie, b: Movie) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct UserReview: Identifiable, Codable, Hashable {
    // ts doubles as the stable local id (the backend keys reviews by
    // user_id + movie_id), same convention as App.jsx userReviews.
    var ts: Date
    var movieId: String
    var movieTitle: String
    var rating: Int
    var text: String
    var edited: Bool = false
    var id: Date { ts }
}

struct Toast: Equatable {
    enum Tone { case ok, error, warn }
    var message: String
    var tone: Tone
    var id = UUID()
}
