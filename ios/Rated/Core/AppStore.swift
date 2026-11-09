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
    var email: String?

    // MARK: Library
    var rankedIds: [String] = [] { didSet { persistLibrary() } }
    var eloScores: [String: Int] = [:] { didSet { persistLibrary() } }
    var rankCount = 0
    var savedMovies: Set<String> = []
    var userReviews: [UserReview] = []

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
        static let onboardingDone = "rated_onboarding_done"
    }

    init() {
        if ProcessInfo.processInfo.arguments.contains("-uitest-reset") { Self.wipePersisted() }
        onboardingDone = UserDefaults.standard.bool(forKey: Keys.onboardingDone)
        restoring = true
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
        username = ""; displayName = ""; email = nil
        restoring = true
        rankedIds = []; eloScores = [:]
        restoring = false
        userReviews = []; searchHistory = []
        savedMovies = []
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
        async let sv = api.saved(uid, token: s)
        async let rv = api.reviews(uid, token: s)
        async let rk = api.rankings(uid, token: s)
        let saved = await sv, reviews = await rv
        await Catalog.shared.resolveUnknown((saved ?? []) + (reviews ?? []).map(\.movie_id))
        if let v = saved { savedMovies = Set(v) }
        if let r = reviews {
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
                if Catalog.shared.find(m.movie_id)?.posterURL == nil, m.title != nil {
                    Catalog.shared.register([Catalog.movie(m)])
                }
            }
            // Keep local order when it's the same set (local drag-reorders aren't
            // stored server-side); otherwise adopt the backend's score order.
            if Set(ids) != Set(rankedIds) { rankedIds = ids }
            eloScores.merge(scores) { local, _ in local }
        }
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

    // MARK: - Reviews

    func submitReview(movie: Movie, rating: Int, text: String) {
        let ts = Date.now
        userReviews.removeAll { $0.movieId == movie.id }
        userReviews.insert(UserReview(ts: ts, movieId: movie.id, movieTitle: movie.title, rating: rating, text: text), at: 0)
        guard let uid = userId, let s = session else { return }
        Task {
            if await !api.submitReview(uid, movie: movie, rating: rating, text: text, token: s) {
                userReviews.removeAll { $0.ts == ts }
                showToast("Couldn't post review", .error)
            }
        }
    }

    func editReview(_ review: UserReview, text: String, rating: Int) {
        guard let i = userReviews.firstIndex(where: { $0.ts == review.ts }) else { return }
        userReviews[i].text = text
        userReviews[i].rating = rating
        userReviews[i].edited = true
        guard let uid = userId, let s = session else { return }
        let movie = Catalog.shared.find(review.movieId, title: review.movieTitle)!
        Task { if await !api.submitReview(uid, movie: movie, rating: rating, text: text, token: s) { showToast("Couldn't save changes", .error) } }
    }

    func deleteReview(_ review: UserReview) {
        userReviews.removeAll { $0.ts == review.ts }
        guard let uid = userId, let s = session else { return }
        Task { if await !api.deleteReview(uid, movieId: review.movieId, token: s) { showToast("Couldn't delete review", .error) } }
    }

    // MARK: - Rankings

    func startRank(_ movie: Movie) {
        Haptics.medium()
        if rankedIds.contains(movie.id) {
            showToast("Already ranked")
            return
        }
        rankTarget = movie
    }

    /// Commit a finished RankSession: persist Elo + order and send pairwise + final score to the backend.
    func completeRank(_ session: RankSession, movie: Movie) {
        let ids = session.finalIds
        eloScores = session.elo
        rankedIds = ids
        rankCount += 1
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

    func updateProfile(name: String) {
        displayName = name
        persistSession()
        if let uid = userId, let s = session { Task { _ = await api.updateProfile(uid, fields: ["name": name], token: s) } }
    }

    func changeUsername(_ u: String) async -> Bool {
        if let s = session {
            do { try await api.setUsername(u, token: s) } catch { showToast(error.localizedDescription, .error); return false }
        }
        username = u
        persistSession()
        return true
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
        var expiresAt: Double?
        var email: String?
    }

    private func persistSession(expiresAt: Double? = nil) {
        guard let uid = userId, let s = session else { return }
        Keychain.set(s, for: "session_token")
        var prev = (UserDefaults.standard.data(forKey: Keys.auth)).flatMap { try? JSONDecoder().decode(SavedSession.self, from: $0) }
        let exp = expiresAt ?? prev?.expiresAt
        prev = SavedSession(provider: provider, userId: uid, username: username, displayName: displayName,
                            expiresAt: exp, email: email)
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
        email = saved.email
        authState = saved.username.isEmpty ? .choosingUsername : .loggedIn
        if authState == .loggedIn { Task { await hydrate() } }
    }

    private struct SavedLibrary: Codable { var rankedIds: [String]; var elo: [String: Int]; var movies: [Movie]? }

    private func persistLibrary() {
        guard !restoring else { return }
        let lib = SavedLibrary(rankedIds: rankedIds, elo: eloScores,
                               movies: rankedIds.compactMap { Catalog.shared.find($0) }.filter { $0.title != "Unknown" })
        UserDefaults.standard.set(try? JSONEncoder().encode(lib), forKey: Keys.library)
    }

    private func restoreLibrary() {
        guard let d = UserDefaults.standard.data(forKey: Keys.library),
              let lib = try? JSONDecoder().decode(SavedLibrary.self, from: d) else { return }
        rankedIds = lib.rankedIds
        eloScores = lib.elo
        Catalog.shared.register(lib.movies ?? [])
    }

    private static func wipePersisted(keepOnboarding: Bool = false) {
        let d = UserDefaults.standard
        for k in [Keys.auth, Keys.library] { d.removeObject(forKey: k) }
        if !keepOnboarding { d.removeObject(forKey: Keys.onboardingDone) }
        Keychain.delete("session_token")
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
