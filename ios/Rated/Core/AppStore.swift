import Foundation
import Network
import Observation
import SwiftUI
import UIKit

enum AuthState: String, Codable { case loggedOut, choosingUsername, loggedIn }
enum LoginProvider: String, Codable { case apple, google }

enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

/// App-wide state — the SwiftUI port of App.jsx's AppInner. Every mutation is
/// optimistic: local state flips first, the backend write follows, and a
/// failed write rolls back with a toast. Without a session the app runs in
/// local-only mode so demos work offline.
@MainActor
@Observable
final class AppStore {
    // MARK: Auth & profile
    var authState: AuthState = .loggedOut
    var provider: LoginProvider?
    var session: String?
    var userId: String?
    var username = ""
    var displayName = ""
    var bio = ""
    var profilePic: Data?
    var isPrivate = false
    var lastUsernameChange: Date?
    var email: String?

    // MARK: Preferences
    var themeMode: ThemeMode = .dark { didSet { persistPrefs() } }
    var fontScale: CGFloat = 1.0 { didSet { persistPrefs() } }

    // MARK: Library
    var rankedIds: [String] = [] { didSet { persistLibrary() } }
    var eloScores: [String: Int] = [:] { didSet { persistLibrary() } }
    var rankHistory: [RankEvent] = [] { didSet { persistLibrary() } }
    var watchlist: Set<String> = []
    var savedMovies: Set<String> = ["m-001", "m-002", "m-005"]
    var userReviews: [UserReview] = []
    var userFeedItems: [FeedItem] = []

    // MARK: Social
    var feedLikes: [String: Bool] = [:]
    var replies: [String: [Reply]] = Mock.seedReplies
    var followingHandles: Set<String> = Set(Mock.friends.filter(\.isFollowing).map { "@\($0.username)" })
    var blockedUsers: Set<String> = []
    var approvedFollowers: Set<String> = []
    var followTimestamps: [Date] = []
    var unreadCount = 3
    var searchHistory: [String] = []

    // MARK: Flow
    var onboardingActive = false
    var onboardingDone = false
    var rankTarget: Movie?
    var toast: Toast?
    var online = true

    private let api = APIClient.shared
    private let pathMonitor = NWPathMonitor()
    private var restoring = false

    private enum Keys {
        static let auth = "rated:auth"
        static let library = "rated:library"
        static let prefs = "rated:prefs"
        static let onboardingDone = "rated_onboarding_done"
    }

    init() {
        if ProcessInfo.processInfo.arguments.contains("-uitest-reset") { Self.wipePersisted() }
        onboardingDone = UserDefaults.standard.bool(forKey: Keys.onboardingDone)
        restoring = true
        restorePrefs()
        restoreLibrary()
        restoreSession()
        restoring = false
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.online = path.status == .satisfied }
        }
        pathMonitor.start(queue: .global(qos: .utility))
    }

    var isAuthed: Bool { userId != nil && session != nil }
    var handle: String { username.isEmpty ? "@you" : "@\(username)" }
    var avatarInitial: String { String((displayName.isEmpty ? (username.isEmpty ? "Y" : username) : displayName).prefix(1)).uppercased() }
    var streak: StreakInfo { Streak.compute(rankHistory) }

    // MARK: - Toast

    func showToast(_ message: String, _ tone: Toast.Tone = .ok) {
        let t = Toast(message: message, tone: tone)
        toast = t
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if toast?.id == t.id { toast = nil }
        }
    }

    // MARK: - Auth

    func login(_ provider: LoginProvider) async {
        self.provider = provider
        // Stub "sub|name|email" token accepted by the backend's AuthService when
        // GOOGLE_CLIENT_ID is unset — same dev path as App.jsx handleLogin.
        // UI-test launches get a fresh sub so every run walks the new-user path.
        let suffix = ProcessInfo.processInfo.arguments.contains("-uitest-reset") ? "_\(UUID().uuidString.prefix(8))" : ""
        let idToken = provider == .apple
            ? "sub_apple_ios\(suffix)|Apple User|user@icloud.com"
            : "sub_google_ios\(suffix)|Google User|user@gmail.com"
        switch await api.login(idToken: idToken) {
        case .failure(let e):
            showToast(e.localizedDescription.contains("Could not connect") || e is URLError
                      ? "Couldn't connect to server. Make sure the backend is running."
                      : e.localizedDescription, .error)
        case .success(let res):
            session = res.session_token
            userId = res.user_id
            email = res.user.email
            let existing = res.user.username ?? res.username ?? ""
            if let n = res.user.name, !n.isEmpty { displayName = n }
            if let pic = res.user.avatar_url.flatMap(Self.decodeDataURL) { profilePic = pic }
            isPrivate = res.user.is_private ?? false
            if existing.isEmpty {
                authState = .choosingUsername
            } else {
                username = existing
                authState = .loggedIn
                await hydrate()
            }
            persistSession(expiresAt: res.expires_at)
        }
    }

    func completeUsername(_ u: String, name: String) async {
        username = u
        if !name.isEmpty { displayName = name }
        authState = .loggedIn
        persistSession()
        if isAuthed, !name.isEmpty { _ = await api.updateProfile(userId!, fields: ["name": name], token: session!) }
        if !onboardingDone && rankedIds.isEmpty { onboardingActive = true }
        await hydrate()
    }

    func finishOnboarding() {
        onboardingActive = false
        onboardingDone = true
        UserDefaults.standard.set(true, forKey: Keys.onboardingDone)
    }

    func signOut() {
        Self.wipePersisted(keepOnboarding: true)
        authState = .loggedOut
        provider = nil; session = nil; userId = nil
        username = ""; displayName = ""; bio = ""; profilePic = nil; isPrivate = false; email = nil
        restoring = true
        rankedIds = []; eloScores = [:]; rankHistory = []
        restoring = false
        watchlist = []; userReviews = []; userFeedItems = []; searchHistory = []
        savedMovies = []; feedLikes = [:]; followingHandles = []; blockedUsers = []
        approvedFollowers = []; followTimestamps = []; lastUsernameChange = nil; unreadCount = 0
        onboardingActive = false; rankTarget = nil
    }

    func deleteAccount() async {
        if let uid = userId, let s = session { await api.deleteAccount(uid, token: s) }
        signOut()
    }

    /// Pull the user's library from the backend after login (App.jsx's four
    /// post-login effects). Missing/failed responses leave local state alone.
    func hydrate() async {
        guard let uid = userId, let s = session else { return }
        async let wl = api.watchlist(uid, token: s)
        async let sv = api.saved(uid, token: s)
        async let rv = api.reviews(uid, token: s)
        async let rk = api.rankings(uid, token: s)
        async let lk = api.myFeedLikes(uid)
        if let w = await wl { watchlist = Set(w) }
        if let v = await sv { savedMovies = Set(v) }
        if let r = await rv {
            userReviews = r.map { row in
                UserReview(ts: Date(timeIntervalSince1970: row.created_at ?? Date.now.timeIntervalSince1970),
                           movieId: row.movie_id,
                           movieTitle: Catalog.shared.find(row.movie_id)?.title ?? row.movie_id,
                           rating: row.rating, text: row.text, edited: row.edited ?? false)
            }
        }
        if let rows = await rk, !rows.isEmpty {
            // Backend 1–10 score → local Elo-ish scale (≈20 Elo per point).
            var scores: [String: Int] = [:]
            var ids: [String] = []
            for r in rows {
                guard let m = r.movie else { continue }
                ids.append(m.movie_id)
                if let sc = r.score { scores[m.movie_id] = 1400 + Int(sc * 20) }
                if Catalog.shared.find(m.movie_id)?.posterURL == nil, let t = m.title {
                    Catalog.shared.register([Movie(id: m.movie_id, title: t, releaseYear: m.year, posterURL: m.poster_url, genres: m.genre.map { [$0] } ?? [])])
                }
            }
            // Keep local order when it's the same set (local drag-reorders aren't
            // stored server-side); otherwise adopt the backend's score order.
            if Set(ids) != Set(rankedIds) { rankedIds = ids }
            eloScores.merge(scores) { local, _ in local }
        }
        if let likes = await lk { for id in likes { feedLikes[id] = true } }
    }

    // MARK: - Saved / watchlist

    func toggleSaved(_ movie: Movie) {
        Haptics.light()
        let was = savedMovies.contains(movie.id)
        if was { savedMovies.remove(movie.id) } else { savedMovies.insert(movie.id) }
        guard let uid = userId, let s = session else { return }
        Task {
            if await !api.setSaved(uid, movie: movie, on: !was, token: s) {
                if was { savedMovies.insert(movie.id) } else { savedMovies.remove(movie.id) }
                showToast(was ? "Couldn't unsave" : "Couldn't save", .error)
            }
        }
    }

    func toggleWatchlist(_ id: String) {
        Haptics.light()
        let has = watchlist.contains(id)
        if has { watchlist.remove(id) } else { watchlist.insert(id) }
        guard let uid = userId, let s = session else { return }
        Task {
            if await !api.setWatchlist(uid, movieId: id, on: !has, token: s) {
                if has { watchlist.insert(id) } else { watchlist.remove(id) }
                showToast(has ? "Couldn't remove from watchlist" : "Couldn't add to watchlist", .error)
            }
        }
    }

    // MARK: - Feed likes & replies

    func isLiked(_ item: FeedItem) -> Bool { feedLikes[item.id] ?? item.liked }

    func likeCount(_ item: FeedItem) -> Int {
        let liked = feedLikes[item.id]
        return item.likes + (liked == true && !item.liked ? 1 : 0) - (liked == false && item.liked ? 1 : 0)
    }

    func toggleLike(_ item: FeedItem) {
        Haptics.light()
        feedLikes[item.id] = !isLiked(item)
        if let uid = userId, let s = session { Task { await api.toggleFeedLike(uid, itemId: item.id, token: s) } }
    }

    func postReply(_ itemId: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 280 else { return }
        if Profanity.check(trimmed) != nil { showToast("Reply contains inappropriate language", .error); return }
        replies[itemId, default: []].append(Reply(user: handle, avatar: avatarInitial, text: trimmed, ts: .now))
        if let uid = userId, let s = session { Task { await api.postReply(uid, itemId: itemId, body: trimmed, token: s) } }
    }

    /// Replace seeded/optimistic replies with the backend's canonical thread when it has one.
    func loadReplies(for ids: [String]) async {
        await withTaskGroup(of: (String, [APIReplyRow]?).self) { group in
            for id in ids { group.addTask { (id, await APIClient.shared.replies(id)) } }
            for await (id, rows) in group {
                guard let rows, !rows.isEmpty else { continue }
                replies[id] = rows.map {
                    let u = $0.user?.username ?? $0.user?.name ?? "?"
                    return Reply(user: "@\(u)", avatar: String(u.prefix(1)).uppercased(), text: $0.body,
                                 ts: $0.created_at.map { Date(timeIntervalSince1970: $0) } ?? .now)
                }
            }
        }
    }

    // MARK: - Follow graph & moderation

    /// Returns nil when allowed, else a "try again in N minutes" message.
    func followLimitMessage(now: Date = .now) -> String? {
        let recent = followTimestamps.filter { now.timeIntervalSince($0) < Moderation.followWindow }
        guard recent.count >= Moderation.followLimitPerHour, let oldest = recent.min() else { return nil }
        let minLeft = Int(ceil((Moderation.followWindow - now.timeIntervalSince(oldest)) / 60))
        return "Follow limit reached (\(Moderation.followLimitPerHour)/hour). Try again in \(minLeft) minute\(minLeft == 1 ? "" : "s")."
    }

    /// Follow (rate-limited) or unfollow (instant) by @handle.
    func toggleFollow(_ handle: String) {
        let was = followingHandles.contains(handle)
        if !was {
            if let msg = followLimitMessage() { showToast(msg, .error); return }
            followTimestamps = followTimestamps.filter { Date.now.timeIntervalSince($0) < Moderation.followWindow } + [.now]
        }
        Haptics.light()
        if was { followingHandles.remove(handle) } else { followingHandles.insert(handle) }
        guard let uid = userId, let s = session else { return }
        Task {
            // Mock handles have no backend row — leave the optimistic state as-is.
            guard let target = await api.userByUsername(handle, token: s) else { return }
            let ok = was ? await api.unfollow(uid, followee: target.user_id, token: s)
                         : await api.follow(uid, followee: target.user_id, token: s)
            if !ok {
                if was { followingHandles.insert(handle) } else { followingHandles.remove(handle) }
                showToast(was ? "Couldn't unfollow" : "Couldn't follow", .error)
            }
        }
    }

    func approveFollower(_ handle: String) { approvedFollowers.insert(handle) }

    func block(_ handle: String) {
        blockedUsers.insert(handle)
        followingHandles.remove(handle)
        approvedFollowers.remove(handle)
        showToast("Blocked \(handle) · They can no longer see or follow you")
    }

    func unblock(_ handle: String) {
        blockedUsers.remove(handle)
        showToast("Unblocked \(handle)")
    }

    func report(type: String, targetId: String, label: String, reason: ReportReason) {
        if let uid = userId, let s = session {
            Task { await api.submitReport(uid, type: type, targetId: targetId, label: label, reason: reason, token: s) }
        }
        showToast("Report received")
    }

    // MARK: - Reviews

    func submitReview(movie: Movie, rating: Int, text: String) {
        let ts = Date.now
        userReviews.insert(UserReview(ts: ts, movieId: movie.id, movieTitle: movie.title, rating: rating, text: text), at: 0)
        let feedId = "self-review-\(Int(ts.timeIntervalSince1970 * 1000))"
        userFeedItems.insert(FeedItem(id: feedId, type: .review, user: handle, avatar: avatarInitial, action: "reviewed",
                                      movieTitle: movie.title, movieId: movie.id, rating: Double(rating), preview: text, ts: ts), at: 0)
        guard let uid = userId, let s = session else { return }
        Task {
            if await !api.submitReview(uid, movie: movie, rating: rating, text: text, token: s) {
                userReviews.removeAll { $0.ts == ts }
                userFeedItems.removeAll { $0.id == feedId }
                showToast("Couldn't post review", .error)
            }
        }
    }

    func editReview(_ review: UserReview, text: String, rating: Int) {
        guard let i = userReviews.firstIndex(where: { $0.ts == review.ts }) else { return }
        userReviews[i].text = text
        userReviews[i].rating = rating
        userReviews[i].edited = true
        let feedId = "self-review-\(Int(review.ts.timeIntervalSince1970 * 1000))"
        if let j = userFeedItems.firstIndex(where: { $0.id == feedId }) {
            userFeedItems[j].preview = text
            userFeedItems[j].rating = Double(rating)
        }
        guard let uid = userId, let s = session else { return }
        let movie = Catalog.shared.find(review.movieId, title: review.movieTitle)!
        Task { if await !api.submitReview(uid, movie: movie, rating: rating, text: text, token: s) { showToast("Couldn't save changes", .error) } }
    }

    func deleteReview(_ review: UserReview) {
        userReviews.removeAll { $0.ts == review.ts }
        userFeedItems.removeAll { $0.id == "self-review-\(Int(review.ts.timeIntervalSince1970 * 1000))" }
        guard let uid = userId, let s = session else { return }
        Task { if await !api.deleteReview(uid, movieId: review.movieId, token: s) { showToast("Couldn't delete review", .error) } }
    }

    // MARK: - Rankings

    func startRank(_ movie: Movie) {
        Haptics.medium()
        if rankedIds.contains(movie.id) {
            showToast("Already ranked · re-rank from your profile")
            return
        }
        rankTarget = movie
    }

    func reRank(_ movie: Movie) {
        unrank(movie.id)
        rankTarget = movie
    }

    func unrank(_ id: String) {
        rankedIds.removeAll { $0 == id }
        eloScores[id] = nil
        userFeedItems.removeAll { $0.movieId == id && $0.type == .ranking }
    }

    func moveRanking(from source: IndexSet, to destination: Int) {
        rankedIds.move(fromOffsets: source, toOffset: destination)
    }

    func moveRanking(_ id: String, to index: Int) {
        guard let from = rankedIds.firstIndex(of: id) else { return }
        rankedIds.remove(at: from)
        rankedIds.insert(id, at: max(0, min(index, rankedIds.count)))
    }

    /// Commit a finished RankSession: persist Elo + order, log streak history,
    /// post a feed item, and send pairwise + final score to the backend.
    func completeRank(_ session: RankSession, movie: Movie) {
        let ids = session.finalIds
        eloScores = session.elo
        rankedIds = ids
        let now = Date.now
        rankHistory.append(RankEvent(movieId: movie.id, ts: now))
        let pos = (ids.firstIndex(of: movie.id) ?? 0) + 1
        userFeedItems.insert(FeedItem(id: "self-rank-\(Int(now.timeIntervalSince1970 * 1000))", type: .ranking, user: handle, avatar: avatarInitial,
                                      action: "ranked a new film", movieTitle: movie.title, movieId: movie.id,
                                      rating: Double(Elo.score(position: pos, total: ids.count)),
                                      preview: "Ranked #\(pos) of \(ids.count)", rankPosition: pos, ts: now), at: 0)
        rankTarget = nil
        Haptics.success()
        guard let uid = userId, let s = self.session else { return }
        let comparisons = session.comparisons
        let score = Elo.score(fromElo: session.elo[movie.id] ?? 1500)
        Task {
            for c in comparisons { await api.recordPairwise(uid, winner: c.winner, loser: c.loser, token: s) }
            if await !api.addRanking(uid, movie: movie, score: score, token: s) { showToast("Saved locally · couldn't sync ranking", .warn) }
        }
    }

    // MARK: - Profile edits

    func updateProfile(name: String, bio newBio: String) {
        displayName = name
        bio = newBio
        persistSession()
        if let uid = userId, let s = session { Task { _ = await api.updateProfile(uid, fields: ["name": name, "bio": newBio], token: s) } }
    }

    func updateProfilePic(_ jpeg: Data) {
        profilePic = jpeg
        persistSession()
        guard let uid = userId, let s = session else { return }
        let dataURL = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        Task {
            if await !api.updateProfile(uid, fields: ["avatar_url": dataURL], token: s) {
                showToast("Couldn't save photo to server — it'll show locally only.", .warn)
            }
        }
    }

    func changeUsername(_ u: String) async -> Bool {
        if let s = session {
            do { try await api.setUsername(u, token: s) } catch { showToast(error.localizedDescription, .error); return false }
        }
        Usernames.taken.insert(u)
        username = u
        lastUsernameChange = .now
        persistSession()
        return true
    }

    func setPrivate(_ on: Bool) {
        isPrivate = on
        if let uid = userId, let s = session { Task { _ = await api.updateProfile(uid, fields: ["is_private": on ? "true" : "false"], token: s) } }
    }

    // MARK: - Search history

    func addSearchHistory(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { return }
        searchHistory = Array(([t] + searchHistory.filter { $0.lowercased() != t.lowercased() }).prefix(10))
    }

    // MARK: - Persistence
    // Session token lives in the Keychain; profile/library/prefs in UserDefaults.

    private struct SavedSession: Codable {
        var provider: LoginProvider?
        var userId: String
        var username: String
        var displayName: String
        var bio: String
        var expiresAt: Double?
        var lastUsernameChange: Date?
        var email: String?
    }

    private func persistSession(expiresAt: Double? = nil) {
        guard let uid = userId, let s = session else { return }
        Keychain.set(s, for: "session_token")
        if let pic = profilePic { UserDefaults.standard.set(pic, forKey: Keys.auth + ":pic") }
        var prev = (UserDefaults.standard.data(forKey: Keys.auth)).flatMap { try? JSONDecoder().decode(SavedSession.self, from: $0) }
        let exp = expiresAt ?? prev?.expiresAt
        prev = SavedSession(provider: provider, userId: uid, username: username, displayName: displayName, bio: bio,
                            expiresAt: exp, lastUsernameChange: lastUsernameChange, email: email)
        UserDefaults.standard.set(try? JSONEncoder().encode(prev), forKey: Keys.auth)
    }

    private func restoreSession() {
        guard let data = UserDefaults.standard.data(forKey: Keys.auth),
              let saved = try? JSONDecoder().decode(SavedSession.self, from: data),
              let token = Keychain.get("session_token") else { return }
        if let exp = saved.expiresAt, exp < Date.now.timeIntervalSince1970 { Self.wipePersisted(keepOnboarding: true); return }
        session = token
        userId = saved.userId
        provider = saved.provider
        username = saved.username
        displayName = saved.displayName
        bio = saved.bio
        email = saved.email
        lastUsernameChange = saved.lastUsernameChange
        profilePic = UserDefaults.standard.data(forKey: Keys.auth + ":pic")
        authState = saved.username.isEmpty ? .choosingUsername : .loggedIn
        if authState == .loggedIn { Task { await hydrate() } }
    }

    private struct SavedLibrary: Codable { var rankedIds: [String]; var elo: [String: Int]; var history: [RankEvent] }

    private func persistLibrary() {
        guard !restoring else { return }
        let lib = SavedLibrary(rankedIds: rankedIds, elo: eloScores, history: rankHistory)
        UserDefaults.standard.set(try? JSONEncoder().encode(lib), forKey: Keys.library)
    }

    private func restoreLibrary() {
        guard let d = UserDefaults.standard.data(forKey: Keys.library),
              let lib = try? JSONDecoder().decode(SavedLibrary.self, from: d) else { return }
        rankedIds = lib.rankedIds
        eloScores = lib.elo
        rankHistory = lib.history
    }

    private func persistPrefs() {
        guard !restoring else { return }
        UserDefaults.standard.set(["theme": themeMode.rawValue, "scale": Double(fontScale)], forKey: Keys.prefs)
    }

    private func restorePrefs() {
        guard let p = UserDefaults.standard.dictionary(forKey: Keys.prefs) else { return }
        themeMode = (p["theme"] as? String).flatMap(ThemeMode.init) ?? .dark
        fontScale = CGFloat(p["scale"] as? Double ?? 1.0)
    }

    private static func wipePersisted(keepOnboarding: Bool = false) {
        let d = UserDefaults.standard
        for k in [Keys.auth, Keys.auth + ":pic", Keys.library] { d.removeObject(forKey: k) }
        if !keepOnboarding { d.removeObject(forKey: Keys.onboardingDone); d.removeObject(forKey: Keys.prefs) }
        Keychain.delete("session_token")
    }

    private static func decodeDataURL(_ s: String) -> Data? {
        guard s.hasPrefix("data:"), let comma = s.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(s[s.index(after: comma)...]))
    }
}

/// Minimal generic-password Keychain wrapper for the session token.
enum Keychain {
    private static let service = "com.iamjasonbian.rated"

    static func set(_ value: String, for key: String) {
        delete(key)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecValueData as String: Data(value.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}
