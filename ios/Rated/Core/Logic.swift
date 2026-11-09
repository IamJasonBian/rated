import Foundation

// Pure logic ported from build/src/lib/{elo,profanity,time,usernames}.js.
// Kept free of UI/state so RatedTests can exercise it directly.

enum Elo {
    /// Standard Elo update; returns `(winnerNew, loserNew)`. K=32 as in elo.js.
    static func update(winner: Int, loser: Int, k: Double = 32) -> (Int, Int) {
        let expected = 1 / (1 + pow(10, Double(loser - winner) / 400))
        return (Int((Double(winner) + k * (1 - expected)).rounded()),
                Int((Double(loser) + k * (0 - (1 - expected))).rounded()))
    }

    /// Elo → 1–10 backend score (1500 ≈ 5, ±20 per step), as in RankScreen.handleSave.
    static func score(fromElo elo: Int) -> Int {
        min(10, max(1, Int((Double(elo - 1400) / 20).rounded())))
    }
}

/// Binary-search insertion ranker (RankScreen.jsx). Bisects the existing list
/// with ~log2(n) head-to-head picks, applying an Elo update on each pick.
struct RankSession {
    let newId: String
    let rankedIds: [String]
    private(set) var lo = 0
    private(set) var hi: Int
    private(set) var elo: [String: Int]
    private(set) var pending: (chosen: String, other: String, nextLo: Int, nextHi: Int)?
    private(set) var insertPos: Int?
    private(set) var comparisons: [(winner: String, loser: String)] = []

    init(newId: String, rankedIds: [String], elo: [String: Int]) {
        self.newId = newId
        self.rankedIds = rankedIds
        self.hi = rankedIds.count
        var e = elo
        e[newId] = 1500
        self.elo = e
        if rankedIds.isEmpty { insertPos = 0 }
    }

    var isDone: Bool { insertPos != nil }
    var midIdx: Int { (lo + hi) / 2 }
    var opponentId: String? { isDone || rankedIds.isEmpty ? nil : rankedIds[midIdx] }
    var remaining: Int { hi - lo }
    var estimatedTotal: Int { max(1, Int(ceil(log2(Double(rankedIds.count + 1))))) }
    var progress: Double {
        guard !rankedIds.isEmpty else { return 1 }
        return max(0.05, 1 - Double(hi - lo) / Double(rankedIds.count))
    }
    var willFinishOnAdvance: Bool { pending.map { $0.nextLo >= $0.nextHi } ?? false }

    mutating func pick(_ winnerId: String) {
        guard let opp = opponentId, pending == nil else { return }
        let loserId = winnerId == newId ? opp : newId
        let (w, l) = Elo.update(winner: elo[winnerId] ?? 1500, loser: elo[loserId] ?? 1500)
        elo[winnerId] = w
        elo[loserId] = l
        comparisons.append((winnerId, loserId))
        let newWins = winnerId == newId
        pending = (winnerId, loserId, newWins ? lo : midIdx + 1, newWins ? midIdx : hi)
    }

    mutating func advance() {
        guard let p = pending else { return }
        pending = nil
        if p.nextLo >= p.nextHi { insertPos = p.nextLo } else { lo = p.nextLo; hi = p.nextHi }
    }

    var finalIds: [String] {
        var ids = rankedIds
        ids.insert(newId, at: min(insertPos ?? 0, ids.count))
        return ids
    }
}

/// Basic word-list profanity filter with leetspeak normalisation (profanity.js).
enum Profanity {
    private static let words = [
        "fuck", "shit", "cunt", "bitch", "bastard", "asshole", "dick", "piss",
        "cock", "pussy", "slut", "whore",
        "nigger", "nigga", "faggot", "fag", "retard", "tranny", "spic", "chink",
        "kike", "wetback", "gook",
        "rape", "raping", "kys", "kms", "killyourself",
    ]
    private static let leet: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
        "@": "a", "$": "s", "!": "i", "+": "t",
    ]

    static func normalize(_ text: String) -> String {
        let mapped = String(text.lowercased().map { leet[$0] ?? $0 })
        let spaced = mapped.map { ($0.isASCII && ($0.isLetter || $0.isNumber)) ? $0 : " " }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }

    /// Returns the matched word, or nil when the text is clean.
    static func check(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let n = normalize(text)
        return words.first { n.contains($0) }
    }
}

enum Usernames {
    static func sanitize(_ raw: String) -> String {
        String(raw.lowercased().filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" })
    }

    /// Client-side format check; nil when the handle is locally valid.
    static func localError(_ v: String) -> String? {
        if v.isEmpty { return nil }
        if v.count < 4 { return "At least 4 characters" }
        if v.count > 20 { return "Max 20 characters" }
        if sanitize(v) != v { return "Only lowercase letters, numbers, and _" }
        if Profanity.check(v) != nil { return "Username contains inappropriate language" }
        return nil
    }
}

enum TimeFmt {
    static func relative(_ date: Date, now: Date = .now) -> String {
        let diff = now.timeIntervalSince(date)
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = diff < 365 * 86400 ? "MMM d" : "MMM d, yyyy"
        return f.string(from: date)
    }
}

enum Medal {
    static func label(_ index: Int) -> String {
        "\(index + 1)"
    }
}
