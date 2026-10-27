import Foundation

// Port of build/src/lib/mockData.js. Seeds the catalog, feeds and social graph
// so the app stays usable when the backend or TMDB proxy is unreachable.
enum Mock {
    static let tmdbImg = "https://image.tmdb.org/t/p"

    static let movies: [Movie] = [
        Movie(id: "m-001", title: "Interstellar", releaseYear: 2014, runtimeMinutes: 169, contentRating: "PG-13",
              synopsis: "A team of explorers travel through a wormhole in space in an attempt to ensure humanity's survival.",
              originalLanguage: "en",
              posterURL: "\(tmdbImg)/w500/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg",
              backdropURL: "\(tmdbImg)/w1280/xJHokMbljXjADYdit5fK1DVfjko.jpg",
              genres: ["Sci-Fi", "Drama", "Adventure"], directors: ["Christopher Nolan"],
              cast: [.init(name: "Matthew McConaughey", character: "Cooper"), .init(name: "Anne Hathaway", character: "Brand"), .init(name: "Jessica Chastain", character: "Murph")],
              trailers: [.init(title: "Official Trailer", videoKey: "zSWdZVtXT7E", isPrimary: true)],
              keywords: ["space", "wormhole", "nasa", "black hole", "time travel"],
              imdbRating: 8.7, rottenTomatoes: 73, globalElo: 1952, globalRank: 1, avgUserRating: 9.2,
              userRatingCount: 3241, reviewCount: 47, trendingRank: 3, watchlistCount: 1247, seenCount: 8934, isHighlighted: true),
        Movie(id: "m-002", title: "Parasite", originalTitle: "기생충", releaseYear: 2019, runtimeMinutes: 132, contentRating: "R",
              synopsis: "Greed and class discrimination threaten the newly formed symbiotic relationship between the wealthy Park family and the destitute Kim clan.",
              originalLanguage: "ko", isInternational: true,
              posterURL: "\(tmdbImg)/w500/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg",
              backdropURL: "\(tmdbImg)/w1280/TU9NIjwzjoKPwQHoHshkFcQUCG.jpg",
              genres: ["Thriller", "Drama", "Comedy"], directors: ["Bong Joon-ho"],
              cast: [.init(name: "Song Kang-ho", character: "Ki-taek"), .init(name: "Choi Woo-shik", character: "Ki-woo")],
              trailers: [.init(title: "Official Trailer", videoKey: "SEUXfv87Wpk", isPrimary: true)],
              keywords: ["class differences", "wealth", "dark comedy", "seoul"],
              imdbRating: 8.5, rottenTomatoes: 98, globalElo: 1845, globalRank: 3, avgUserRating: 9.0,
              userRatingCount: 2890, reviewCount: 62, trendingRank: 8),
        Movie(id: "m-003", title: "The Dark Knight", releaseYear: 2008, runtimeMinutes: 152, contentRating: "PG-13",
              synopsis: "Batman raises the stakes in his war on crime, facing the Joker, a criminal mastermind who plunges Gotham into anarchy.",
              originalLanguage: "en",
              posterURL: "\(tmdbImg)/w500/qJ2tW6WMUDux911r6m7haRef0WH.jpg",
              genres: ["Action", "Crime", "Drama"], directors: ["Christopher Nolan"],
              cast: [.init(name: "Christian Bale", character: "Batman"), .init(name: "Heath Ledger", character: "Joker")],
              trailers: [.init(title: "Official Trailer", videoKey: "EXeTwQWrcwY", isPrimary: true)],
              imdbRating: 9.0, globalElo: 1823, globalRank: 4, avgUserRating: 9.1,
              userRatingCount: 4187, reviewCount: 89, trendingRank: 12, watchlistCount: 982, seenCount: 12034),
        Movie(id: "m-004", title: "Whiplash", releaseYear: 2014, runtimeMinutes: 107, contentRating: "R",
              synopsis: "A promising young drummer enrolls at a cut-throat music conservatory where his dreams of greatness are mentored by an instructor who will stop at nothing.",
              originalLanguage: "en",
              posterURL: "\(tmdbImg)/w500/7fn624j5lj3xTme2SgiLCeuedmO.jpg",
              genres: ["Drama", "Music"], directors: ["Damien Chazelle"],
              cast: [.init(name: "Miles Teller", character: "Andrew"), .init(name: "J.K. Simmons", character: "Fletcher")],
              imdbRating: 8.5, globalElo: 1768, globalRank: 8, avgUserRating: 8.9,
              userRatingCount: 1876, reviewCount: 34, trendingRank: 15, watchlistCount: 567, seenCount: 4521),
        Movie(id: "m-005", title: "RRR", originalTitle: "RRR", releaseYear: 2022, runtimeMinutes: 187,
              synopsis: "A fictitious story about two legendary revolutionaries and their journey away from home before they began fighting for their country in the 1920s.",
              originalLanguage: "te", isInternational: true,
              posterURL: "\(tmdbImg)/w500/ljHw5eIMnki3HekwkKwCCHsRSbH.jpg",
              genres: ["Action", "Drama"], directors: ["S.S. Rajamouli"],
              cast: [.init(name: "N.T. Rama Rao Jr.", character: "Bheem"), .init(name: "Ram Charan", character: "Ram")],
              imdbRating: 7.8, globalElo: 1689, globalRank: 14, avgUserRating: 8.4,
              userRatingCount: 1342, reviewCount: 28, trendingRank: 20, watchlistCount: 892, seenCount: 3214),
    ]

    private static func upcoming(_ id: String, _ title: String, _ date: String, _ synopsis: String, poster: String? = nil,
                                 genres: [String], director: String, cast: [CastMember], hype: Int, reason: String, watching: Int) -> Movie {
        Movie(id: id, title: title, releaseYear: Int(date.prefix(4)), releaseDate: date, synopsis: synopsis,
              posterURL: poster.map { "\(tmdbImg)/w500/\($0)" }, genres: genres, directors: [director], cast: cast,
              watchlistCount: watching, anticipationScore: hype, mustSeeReason: reason)
    }

    // Same fixtures as the web UPCOMING list, with dates rolled forward a year
    // so the "days away" countdowns stay in the future.
    static let upcoming: [Movie] = [
        upcoming("u-001", "The Mummy", "2027-05-15", "A new chapter in the legendary franchise. An ancient terror is unleashed when an expedition unearths something that should have stayed buried.",
                 poster: "wTnV3PCVW5O92JMrFvvrRcV39RU.jpg", genres: ["Horror", "Adventure"], director: "Lee Cronin", cast: [.init(name: "TBA", character: "Lead")], hype: 720, reason: "From the director of Evil Dead Rise", watching: 342),
        upcoming("u-002", "Werwulf", "2026-12-25", "Robert Eggers returns to folk horror territory with a sweeping werewolf epic set in medieval Europe.",
                 genres: ["Horror", "Thriller"], director: "Robert Eggers", cast: [.init(name: "TBA", character: "Lead")], hype: 890, reason: "Robert Eggers' werewolf epic", watching: 512),
        upcoming("u-003", "Resident Evil", "2027-08-14", "A new cinematic take on the iconic survival horror franchise from the director who brought us Barbarian.",
                 genres: ["Horror", "Action", "Sci-Fi"], director: "Zach Cregger", cast: [.init(name: "TBA", character: "Lead")], hype: 810, reason: "From the Barbarian director", watching: 289),
        upcoming("u-004", "Scary Movie 6", "2027-07-04", "The Wayans brothers reunite for the long-awaited sixth installment of the beloved parody franchise.",
                 genres: ["Comedy", "Horror"], director: "Keenen Ivory Wayans", cast: [.init(name: "TBA", character: "Lead")], hype: 540, reason: "Wayans brothers return", watching: 198),
        upcoming("u-005", "Blade", "2027-09-20", "Marvel's Daywalker returns in a gritty new MCU solo outing.",
                 genres: ["Action", "Sci-Fi", "Horror"], director: "Yann Demange", cast: [.init(name: "Mahershala Ali", character: "Blade")], hype: 870, reason: "Mahershala Ali as Blade", watching: 678),
        upcoming("u-006", "28 Years Later", "2027-06-20", "Danny Boyle returns to the world that defined a generation of horror.",
                 genres: ["Horror", "Thriller", "Drama"], director: "Danny Boyle", cast: [.init(name: "Jodie Comer", character: "Lead"), .init(name: "Aaron Taylor-Johnson", character: "Lead")], hype: 950, reason: "Danny Boyle returns to 28 Days Later", watching: 891),
        upcoming("u-007", "Sinners", "2027-04-18", "Ryan Coogler's blues-soaked supernatural thriller set in 1930s Mississippi.",
                 genres: ["Horror", "Drama", "Thriller"], director: "Ryan Coogler", cast: [.init(name: "Michael B. Jordan", character: "Twins"), .init(name: "Hailee Steinfeld", character: "Mary")], hype: 990, reason: "Ryan Coogler + Michael B. Jordan", watching: 1203),
        upcoming("u-008", "Final Destination: Bloodlines", "2027-05-16", "Death's design returns. A new group of survivors cheat death — and then it starts collecting.",
                 genres: ["Horror", "Thriller"], director: "Zach Lipovsky", cast: [.init(name: "Kaitlyn Santa Juana", character: "Lead")], hype: 730, reason: "The franchise is back", watching: 445),
        upcoming("u-009", "F1", "2027-06-27", "Brad Pitt plays a retired F1 driver who returns to race alongside a rookie.",
                 genres: ["Drama", "Action"], director: "Joseph Kosinski", cast: [.init(name: "Brad Pitt", character: "Sonny Hayes"), .init(name: "Damson Idris", character: "Joshua Pierce")], hype: 840, reason: "Brad Pitt + real F1 footage", watching: 567),
        upcoming("u-010", "Mission: Impossible 8", "2027-05-23", "Ethan Hunt faces his most dangerous mission yet in the final chapter of the beloved franchise.",
                 genres: ["Action", "Thriller"], director: "Christopher McQuarrie", cast: [.init(name: "Tom Cruise", character: "Ethan Hunt")], hype: 920, reason: "Tom Cruise's final Mission", watching: 1102),
    ]

    static let allGenres = ["All", "Horror", "Action", "Drama", "Comedy", "Sci-Fi", "Thriller"]

    private static func ago(_ s: String) -> Date { TimeFmt.parseRelative(s) }

    static let followingFeed: [FeedItem] = [
        FeedItem(id: "f-001", type: .rating, user: "@maya", avatar: "M", action: "rated", movieTitle: "Interstellar", movieId: "m-001", rating: 9.5, ts: ago("2m"), likes: 12),
        FeedItem(id: "f-002", type: .review, user: "@josh", avatar: "J", action: "reviewed", movieTitle: "Parasite", movieId: "m-002", rating: 9.0, preview: "Bong Joon-ho crafted something that transcends genre. The tonal shifts are masterful...", ts: ago("18m"), likes: 34),
        FeedItem(id: "f-003", type: .ranking, user: "@lina", avatar: "L", action: "ranked", movieTitle: "The Dark Knight", movieId: "m-003", rating: 10, preview: "New #1 · dethroned Interstellar", rankPosition: 1, ts: ago("1h"), likes: 8),
        FeedItem(id: "f-004", type: .save, user: "@carlos", avatar: "C", action: "saved", movieTitle: "RRR", movieId: "m-005", ts: ago("2h"), likes: 3),
        FeedItem(id: "f-005", type: .streak, user: "@maya", avatar: "M", action: "hit a 12-week streak 🔥", ts: ago("3h"), likes: 45),
        FeedItem(id: "f-006", type: .rating, user: "@filmfreak", avatar: "F", action: "rated", movieTitle: "The Dark Knight", movieId: "m-003", rating: 10, ts: ago("5h"), likes: 9),
        FeedItem(id: "f-007", type: .rating, user: "@cinephile99", avatar: "C", action: "rated", movieTitle: "Whiplash", movieId: "m-004", rating: 9, ts: ago("6h"), likes: 15),
        FeedItem(id: "f-008", type: .review, user: "@reeltalks", avatar: "R", action: "reviewed", movieTitle: "Interstellar", movieId: "m-001", rating: 9.5, preview: "Nolan's time-dilation sequence still wrecks me...", ts: ago("8h"), likes: 22),
    ]

    static let globalFeed: [FeedItem] = [
        FeedItem(id: "g-001", type: .rating, user: "@cinephile99", avatar: "C", action: "rated", movieTitle: "Parasite", movieId: "m-002", rating: 10, ts: ago("5m"), likes: 34),
        FeedItem(id: "g-002", type: .ranking, user: "@reeltalks", avatar: "R", action: "ranked", movieTitle: "Whiplash", movieId: "m-004", rating: 10, preview: "New #1 · dethroned Interstellar", rankPosition: 1, ts: ago("22m"), likes: 18),
        FeedItem(id: "g-003", type: .rating, user: "@filmfreak", avatar: "F", action: "rated", movieTitle: "The Dark Knight", movieId: "m-003", rating: 10, ts: ago("1h"), likes: 9),
        FeedItem(id: "g-004", type: .review, user: "@lina", avatar: "L", action: "reviewed", movieTitle: "RRR", movieId: "m-005", rating: 9, preview: "S.S. Rajamouli delivers pure spectacle unlike anything Hollywood would greenlight...", ts: ago("2h"), likes: 27),
        FeedItem(id: "g-005", type: .streak, user: "@cinephile99", avatar: "C", action: "hit a 34-week streak 💎", ts: ago("4h"), likes: 89),
    ]

    static let seedReplies: [String: [Reply]] = [
        "f-001": [
            Reply(user: "@maya", avatar: "M", text: "Whiplash is an all-timer for me too", ts: ago("3m")),
            Reply(user: "@josh", avatar: "J", text: "Better than Birdman? Bold take 🔥", ts: ago("12m")),
        ],
        "g-001": [Reply(user: "@reeltalks", avatar: "R", text: "Parasite deserves every 10/10 it gets", ts: ago("8m"))],
        "g-004": [
            Reply(user: "@maya", avatar: "M", text: "Rajamouli is a master, fully agree", ts: ago("3h")),
            Reply(user: "@carlos", avatar: "C", text: "Need to rewatch this one", ts: ago("2h")),
            Reply(user: "@filmfreak", avatar: "F", text: "That dance sequence lives in my head rent free", ts: ago("45m")),
        ],
    ]

    static let friends: [Friend] = [
        Friend(username: "maya", avatar: "M", isFollowing: false, followsMe: true),
        Friend(username: "josh", avatar: "J", isFollowing: true, followsMe: true),
        Friend(username: "lina", avatar: "L", isFollowing: false, followsMe: false),
        Friend(username: "carlos", avatar: "C", isFollowing: true, followsMe: false),
    ]

    // Ordered list so leaderboard/suggestions are deterministic.
    static let profileOrder = ["@cinephile99", "@filmfreak", "@maya", "@reeltalks", "@jasonk", "@josh", "@lina", "@carlos"]
    static let profiles: [String: UserProfile] = [
        "@cinephile99": .init(username: "cinephile99", avatar: "C", moviesRated: 847, streak: 34, badge: "💎", bio: "Seen everything twice.", followers: 1204, following: 88, isPrivate: false),
        "@filmfreak": .init(username: "filmfreak", avatar: "F", moviesRated: 612, streak: 21, badge: "🏆", bio: "35mm or nothing.", followers: 892, following: 120, isPrivate: false),
        "@maya": .init(username: "maya", avatar: "M", moviesRated: 489, streak: 12, badge: "🏆", bio: "Horror nerd. World cinema devotee.", followers: 567, following: 203, isPrivate: false),
        "@reeltalks": .init(username: "reeltalks", avatar: "R", moviesRated: 356, streak: 8, badge: "🔥", bio: "Film criticism is my cardio.", followers: 341, following: 77, isPrivate: false),
        "@jasonk": .init(username: "jasonk", avatar: "J", moviesRated: 89, streak: 7, badge: "🔥", bio: "Just getting started.", followers: 12, following: 34, isPrivate: false),
        "@josh": .init(username: "josh", avatar: "J", moviesRated: 76, streak: 4, badge: "", bio: "Drama and thrillers mainly.", followers: 45, following: 60, isPrivate: false),
        "@lina": .init(username: "lina", avatar: "L", moviesRated: 63, streak: 3, badge: "", bio: "International cinema fanatic.", followers: 88, following: 91, isPrivate: true),
        "@carlos": .init(username: "carlos", avatar: "C", moviesRated: 41, streak: 1, badge: "", bio: "New here, loving it.", followers: 9, following: 22, isPrivate: false),
    ]

    static let notifications: [AppNotification] = [
        .init(id: "n-001", kind: .follow, read: false, ts: ago("2m"), user: "@cinephile99", avatar: "C", text: "started following you"),
        .init(id: "n-002", kind: .followRequest, read: false, ts: ago("14m"), user: "@filmfreak", avatar: "F", text: "requested to follow you"),
        .init(id: "n-003", kind: .watchlist, read: false, ts: ago("1h"), movie: "Sinners", icon: "🎬", text: "is releasing soon · Add to your watchlist"),
        .init(id: "n-004", kind: .follow, read: true, ts: ago("3h"), user: "@maya", avatar: "M", text: "started following you"),
        .init(id: "n-005", kind: .watchlist, read: true, ts: ago("1d"), movie: "Mission: Impossible 8", icon: "🎬", text: "is releasing in 42 days"),
        .init(id: "n-006", kind: .followRequest, read: true, ts: ago("2d"), user: "@josh", avatar: "J", text: "requested to follow you"),
        .init(id: "n-007", kind: .follow, read: true, ts: ago("3d"), user: "@carlos", avatar: "C", text: "started following you"),
    ]

    struct SeedReview { let id, movieId, movieTitle: String; let rating: Int; let text, time: String }
    static let profileReviews: [SeedReview] = [
        .init(id: "rv-003", movieId: "m-003", movieTitle: "The Dark Knight", rating: 10, text: "Heath Ledger's Joker is one of the greatest performances ever committed to film. Every scene crackles with menace. Nolan at his absolute peak.", time: "2h ago"),
        .init(id: "rv-001", movieId: "m-001", movieTitle: "Interstellar", rating: 9, text: "The third act loses me a bit but the docking scene and Hans Zimmer's score are genuinely transcendent. McConaughey carries this film.", time: "3d ago"),
        .init(id: "rv-002", movieId: "m-002", movieTitle: "Parasite", rating: 10, text: "A masterpiece of genre-blending. The way Bong Joon-ho shifts tone without you ever noticing is pure craft. Second watch is even better.", time: "1w ago"),
    ]

    struct FriendsPick { let rank: Int; let movieId: String; let avg: Double; let ratedBy: [String]; let count: Int }
    static let friendsPicks: [FriendsPick] = [
        .init(rank: 1, movieId: "m-001", avg: 9.4, ratedBy: ["@maya", "@josh"], count: 3),
        .init(rank: 2, movieId: "m-002", avg: 9.1, ratedBy: ["@maya", "@carlos"], count: 2),
        .init(rank: 3, movieId: "m-003", avg: 8.8, ratedBy: ["@josh", "@lina"], count: 3),
        .init(rank: 4, movieId: "m-004", avg: 8.7, ratedBy: ["@maya"], count: 1),
        .init(rank: 5, movieId: "m-005", avg: 8.4, ratedBy: ["@carlos", "@lina"], count: 2),
    ]

    static let reportReasons: [ReportReason] = [
        .init(key: "spam", label: "Spam", desc: "Repetitive, misleading, or promotional"),
        .init(key: "harassment", label: "Harassment or bullying", desc: "Targeted abuse or unwanted contact"),
        .init(key: "hate", label: "Hate speech", desc: "Attacks a protected group or identity"),
        .init(key: "inappropriate", label: "Inappropriate content", desc: "Sexual, violent, or graphic material"),
        .init(key: "impersonation", label: "Impersonation", desc: "Pretending to be someone else"),
        .init(key: "other", label: "Something else", desc: "Doesn't fit the categories above"),
    ]
}
