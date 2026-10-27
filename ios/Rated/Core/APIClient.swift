import Foundation

// Port of build/src/lib/api.js. Bearer token goes in the Authorization header;
// network/non-2xx failures return nil (callers fall back to mock data) except
// 401/403, which surface as `APIError.unauthorized` so auth flows can react.

enum APIError: Error, LocalizedError {
    case unauthorized(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized(let m), .server(let m): m
        }
    }
}

// MARK: - Response shapes (only the fields the app reads)

struct APIUser: Decodable {
    var user_id: String
    var name: String?
    var email: String?
    var avatar_url: String?
    var username: String?
    var is_private: Bool?
    var follower_count: Int?
    var following_count: Int?
}

struct LoginResponse: Decodable {
    var user: APIUser
    var session_token: String
    var expires_at: Double?
    var user_id: String
    var username: String?
}

struct APIMovieRef: Decodable {
    var movie_id: String
    var title: String?
    var genre: String?
    var poster_url: String?
    var year: Int?
}

struct APIRanking: Decodable {
    var movie: APIMovieRef?
    var score: Double?
    var ranked_at: Double?
}

struct APIFeedRow: Decodable {
    var user: APIUser?
    var movie: APIMovieRef
    var score: Double?
    var ranked_at: Double?
}

struct APIReview: Decodable {
    var movie_id: String
    var rating: Int
    var text: String
    var created_at: Double?
    var edited: Bool?
}

struct APINotification: Decodable {
    var id: String
    var type: String
    var read: Bool
    var body: String?
    var created_at: Double?
    var actor: APIUser?
}

struct APINotificationList: Decodable { var items: [APINotification] }
struct APIUsernameCheck: Decodable { var available: Bool }
struct APIFeedLikes: Decodable { var item_ids: [String] }
struct APIReplyRow: Decodable { var user: APIUser?; var body: String; var created_at: Double? }
struct APIReplies: Decodable { var replies: [APIReplyRow] }
struct Empty: Decodable {}

struct APICoRater: Decodable, Hashable { var username: String?; var name: String?; var avatar_url: String?; var score: Double? }
struct APITickets: Decodable {
    var show: Bool
    var co_raters: [APICoRater]?
    var label: String?
    var url: String?
    var affiliate: Bool?
    var provider: String?
}

struct MovieMeta: Encodable {
    var title: String
    var genre: String?
    var poster_url: String?
    var year: Int?

    init(_ m: Movie) {
        title = m.title
        genre = m.genres.first
        poster_url = m.posterURL
        year = m.releaseYear
    }
}

final class APIClient: @unchecked Sendable {
    static let shared = APIClient()
    static let baseOverrideKey = "rated.apiBase"

    /// Resolution order: `-rated.apiBase <url>` launch arg / Settings → Developer
    /// override (both land in UserDefaults), then the per-config Info.plist value.
    var baseURL: String {
        if let o = UserDefaults.standard.string(forKey: Self.baseOverrideKey), !o.isEmpty { return o }
        return (Bundle.main.object(forInfoDictionaryKey: "RatedAPIBase") as? String) ?? "http://localhost:8010"
    }

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 8
        return URLSession(configuration: c)
    }()

    private func send(_ method: String, _ path: String, body: Encodable? = nil, token: String? = nil) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.server("Bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONEncoder().encode(AnyEncodable(body)) }
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            let msg = detail ?? "HTTP \(status)"
            if status == 401 || status == 403 { throw APIError.unauthorized(msg) }
            throw APIError.server(msg)
        }
        return data
    }

    /// Fire a request and decode, returning nil on any non-auth failure.
    func call<T: Decodable>(_ method: String, _ path: String, body: Encodable? = nil, token: String? = nil, as: T.Type = T.self) async -> T? {
        do {
            let data = try await send(method, path, body: body, token: token)
            if T.self == Empty.self { return Empty() as? T }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("[API] \(method) \(path) → \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Raw GET for the TMDB proxy, whose bodies are TMDB's verbatim JSON.
    func raw(_ path: String) async -> Data? {
        try? await send("GET", path)
    }

    private func esc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(.init(charactersIn: "/"))) ?? s
    }

    // MARK: Auth

    /// Login that surfaces the backend's error detail (api.js loginRaw).
    func login(idToken: String) async -> Result<LoginResponse, Error> {
        struct Body: Encodable { var id_token: String }
        do {
            let data = try await send("POST", "/auth/login", body: Body(id_token: idToken))
            return .success(try JSONDecoder().decode(LoginResponse.self, from: data))
        } catch {
            return .failure(error)
        }
    }

    func checkUsername(_ u: String) async -> Bool? {
        await call("GET", "/auth/username/check/\(esc(u))", as: APIUsernameCheck.self)?.available
    }

    func setUsername(_ u: String, token: String) async throws {
        struct Body: Encodable { var username: String }
        _ = try await send("POST", "/auth/username", body: Body(username: u), token: token)
    }

    // MARK: Rankings / feed

    func rankings(_ uid: String, token: String) async -> [APIRanking]? {
        await call("GET", "/users/\(uid)/rankings", token: token)
    }

    func addRanking(_ uid: String, movie: Movie, score: Int, token: String) async -> Bool {
        struct Body: Encodable { var movie_id: String; var score: Int; var movie_meta: MovieMeta }
        return await call("POST", "/users/\(uid)/rankings", body: Body(movie_id: movie.id, score: score, movie_meta: MovieMeta(movie)), token: token, as: Empty.self) != nil
    }

    func recordPairwise(_ uid: String, winner: String, loser: String, token: String) async {
        struct Body: Encodable { var winner_movie_id: String; var loser_movie_id: String }
        _ = await call("POST", "/users/\(uid)/pairwise", body: Body(winner_movie_id: winner, loser_movie_id: loser), token: token, as: Empty.self)
    }

    func feed(_ uid: String, token: String) async -> [APIFeedRow]? {
        await call("GET", "/users/\(uid)/feed", token: token)
    }

    // MARK: Social

    func userByUsername(_ handle: String, token: String?) async -> APIUser? {
        let clean = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        return await call("GET", "/users/by-username/\(esc(clean))", token: token)
    }

    func follow(_ uid: String, followee: String, token: String) async -> Bool {
        struct Body: Encodable { var followee_id: String }
        return await call("POST", "/users/\(uid)/follow", body: Body(followee_id: followee), token: token, as: Empty.self) != nil
    }

    func unfollow(_ uid: String, followee: String, token: String) async -> Bool {
        await call("DELETE", "/users/\(uid)/follow/\(followee)", token: token, as: Empty.self) != nil
    }

    func searchUsers(_ q: String, limit: Int = 20) async -> [APIUser]? {
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        return await call("GET", "/users?q=\(enc)&limit=\(limit)")
    }

    // MARK: Saved / watchlist / reviews

    func saved(_ uid: String, token: String) async -> [String]? { await call("GET", "/users/\(uid)/saved", token: token) }
    func watchlist(_ uid: String, token: String) async -> [String]? { await call("GET", "/users/\(uid)/watchlist", token: token) }

    func setSaved(_ uid: String, movie: Movie, on: Bool, token: String) async -> Bool {
        struct Body: Encodable { var movie_id: String; var movie_meta: MovieMeta }
        if on { return await call("POST", "/users/\(uid)/saved", body: Body(movie_id: movie.id, movie_meta: MovieMeta(movie)), token: token, as: Empty.self) != nil }
        return await call("DELETE", "/users/\(uid)/saved/\(movie.id)", token: token, as: Empty.self) != nil
    }

    func setWatchlist(_ uid: String, movieId: String, on: Bool, token: String) async -> Bool {
        struct Body: Encodable { var movie_id: String }
        if on { return await call("POST", "/users/\(uid)/watchlist", body: Body(movie_id: movieId), token: token, as: Empty.self) != nil }
        return await call("DELETE", "/users/\(uid)/watchlist/\(movieId)", token: token, as: Empty.self) != nil
    }

    func reviews(_ uid: String, token: String) async -> [APIReview]? { await call("GET", "/users/\(uid)/reviews", token: token) }

    func submitReview(_ uid: String, movie: Movie, rating: Int, text: String, token: String) async -> Bool {
        struct Body: Encodable { var movie_id: String; var rating: Int; var text: String; var movie_meta: MovieMeta }
        return await call("POST", "/users/\(uid)/reviews", body: Body(movie_id: movie.id, rating: rating, text: text, movie_meta: MovieMeta(movie)), token: token, as: Empty.self) != nil
    }

    func deleteReview(_ uid: String, movieId: String, token: String) async -> Bool {
        await call("DELETE", "/users/\(uid)/reviews/\(movieId)", token: token, as: Empty.self) != nil
    }

    // MARK: Account

    func updateProfile(_ uid: String, fields: [String: String], token: String) async -> Bool {
        await call("PATCH", "/users/\(uid)", body: fields, token: token, as: Empty.self) != nil
    }

    func deleteAccount(_ uid: String, token: String) async {
        _ = await call("DELETE", "/users/\(uid)", token: token, as: Empty.self)
    }

    // MARK: Notifications / reports / likes / replies

    func notifications(_ uid: String) async -> [APINotification]? {
        await call("GET", "/users/\(uid)/notifications", as: APINotificationList.self)?.items
    }

    func markAllNotificationsRead(_ uid: String) async { _ = await call("POST", "/users/\(uid)/notifications/mark-all-read", as: Empty.self) }
    func markNotificationRead(_ uid: String, id: String) async { _ = await call("POST", "/users/\(uid)/notifications/\(id)/read", as: Empty.self) }
    func deleteNotification(_ uid: String, id: String) async { _ = await call("DELETE", "/users/\(uid)/notifications/\(id)", as: Empty.self) }

    func submitReport(_ uid: String, type: String, targetId: String, label: String, reason: ReportReason, token: String) async {
        let body = ["target_type": type, "target_id": targetId, "target_label": label, "reason_key": reason.key, "reason_label": reason.label]
        _ = await call("POST", "/users/\(uid)/reports", body: body, token: token, as: Empty.self)
    }

    func toggleFeedLike(_ uid: String, itemId: String, token: String) async {
        _ = await call("POST", "/users/\(uid)/feed-likes/\(esc(itemId))", token: token, as: Empty.self)
    }

    func myFeedLikes(_ uid: String) async -> [String]? {
        await call("GET", "/users/\(uid)/feed-likes", as: APIFeedLikes.self)?.item_ids
    }

    func postReply(_ uid: String, itemId: String, body: String, token: String) async {
        _ = await call("POST", "/users/\(uid)/feed-replies/\(esc(itemId))", body: ["body": body], token: token, as: Empty.self)
    }

    func replies(_ itemId: String) async -> [APIReplyRow]? {
        await call("GET", "/feed-items/\(esc(itemId))/replies", as: APIReplies.self)?.replies
    }

    /// Affiliate ticket CTA for a movie the user and someone they follow both rated.
    func tickets(_ uid: String, movieId: String, token: String?) async -> APITickets? {
        await call("GET", "/users/\(uid)/movies/\(esc(movieId))/tickets", token: token)
    }

    func ping() async -> Bool { await raw("/movies/top") != nil }
}

/// Type-erased box so `send` can take any Encodable body.
private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
