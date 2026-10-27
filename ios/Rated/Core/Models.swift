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

// One movie shape for both the released catalog and upcoming releases —
// mirrors the web's movie objects (mockData.js MOVIES/UPCOMING and
// tmdb.js mapTmdbMovie). Equality is by id so sets/selection stay stable
// when a stub is later enriched with TMDB detail.
struct Movie: Identifiable, Codable {
    var id: String
    var tmdbId: Int?
    var title: String
    var originalTitle: String?
    var releaseYear: Int?
    var releaseDate: String?
    var runtimeMinutes: Int?
    var contentRating: String?
    var synopsis: String = ""
    var originalLanguage: String?
    var isInternational: Bool = false
    var posterURL: String?
    var backdropURL: String?
    var genres: [String] = []
    var directors: [String] = []
    var cast: [CastMember] = []
    var trailers: [Trailer] = []
    var keywords: [String] = []
    var imdbRating: Double?
    var rottenTomatoes: Int?
    var globalElo: Int?
    var globalRank: Int?
    var avgUserRating: Double?
    var userRatingCount: Int = 0
    var reviewCount: Int = 0
    var trendingRank: Int?
    var watchlistCount: Int = 0
    var seenCount: Int = 0
    var isHighlighted: Bool = false
    var anticipationScore: Int?
    var mustSeeReason: String?

    var primaryTrailer: Trailer? { trailers.first(where: \.isPrimary) ?? trailers.first }
    var isUpcoming: Bool { id.hasPrefix("u-") || (daysUntilRelease.map { $0 > 0 } ?? false) }

    var daysUntilRelease: Int? { TimeFmt.daysUntil(releaseDate) }

    var runtimeLabel: String? {
        guard let m = runtimeMinutes, m > 0 else { return nil }
        return "\(m / 60)h \(m % 60)m"
    }
}

extension Movie: Hashable {
    static func == (a: Movie, b: Movie) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum FeedType: String, Codable { case rating, review, ranking, save, streak }

struct FeedItem: Identifiable, Codable, Hashable {
    var id: String
    var type: FeedType
    var user: String
    var avatar: String
    var action: String
    var movieTitle: String?
    var movieId: String?
    var rating: Double?
    var preview: String?
    var rankPosition: Int?
    var ts: Date
    var likes: Int = 0
    var liked: Bool = false
}

struct Reply: Codable, Hashable {
    var user: String
    var avatar: String
    var text: String
    var ts: Date
}

struct UserProfile: Codable, Hashable {
    var username: String
    var avatar: String
    var moviesRated: Int
    var streak: Int
    var badge: String
    var bio: String
    var followers: Int
    var following: Int
    var isPrivate: Bool

    static func placeholder(for handle: String) -> UserProfile {
        let name = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        return UserProfile(username: name, avatar: String(name.prefix(1)).uppercased(), moviesRated: 0,
                           streak: 0, badge: "", bio: "", followers: 0, following: 0, isPrivate: false)
    }
}

struct Friend: Hashable {
    var username: String
    var avatar: String
    var isFollowing: Bool
    var followsMe: Bool
}

enum NotificationKind: String, Codable { case follow, followRequest, watchlist }

struct AppNotification: Identifiable, Codable, Hashable {
    var id: String
    var kind: NotificationKind
    var read: Bool
    var ts: Date
    var user: String?
    var avatar: String?
    var movie: String?
    var icon: String?
    var text: String
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

struct RankEvent: Codable, Hashable {
    var movieId: String
    var ts: Date
}

struct Toast: Equatable {
    enum Tone { case ok, error, warn }
    var message: String
    var tone: Tone
    var id = UUID()
}

struct ReportReason: Identifiable, Hashable {
    var key: String
    var label: String
    var desc: String
    var id: String { key }
}
