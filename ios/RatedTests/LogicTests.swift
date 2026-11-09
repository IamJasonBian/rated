import XCTest
@testable import Rated

final class EloTests: XCTestCase {
    func testEqualRatingsMoveSixteenPoints() {
        let (w, l) = Elo.update(winner: 1500, loser: 1500)
        XCTAssertEqual(w, 1516)
        XCTAssertEqual(l, 1484)
    }

    func testUpsetMovesMoreThanExpectedWin() {
        let upset = Elo.update(winner: 1400, loser: 1600).0 - 1400
        let expected = Elo.update(winner: 1600, loser: 1400).0 - 1600
        XCTAssertGreaterThan(upset, expected)
    }

    func testScoreMappingsClampToOneThroughTen() {
        XCTAssertEqual(Elo.score(fromElo: 1500), 5)
        XCTAssertEqual(Elo.score(fromElo: 2000), 10)
        XCTAssertEqual(Elo.score(fromElo: 1000), 1)
    }
}

final class RankSessionTests: XCTestCase {
    func testFirstRankIsImmediatelyDoneAtTop() {
        let s = RankSession(newId: "x", rankedIds: [], elo: [:])
        XCTAssertTrue(s.isDone)
        XCTAssertEqual(s.finalIds, ["x"])
    }

    /// Simulate a user with a fixed true preference order and check the
    /// bisection inserts the new movie at its true position for every slot.
    func testBisectionFindsTruePositionForEveryInsertionPoint() {
        let existing = (0..<9).map { "m\($0)" }
        for truePos in 0...existing.count {
            var truth = existing
            truth.insert("new", at: truePos)
            var s = RankSession(newId: "new", rankedIds: existing, elo: [:])
            var picks = 0
            while !s.isDone {
                let opp = s.opponentId!
                s.pick(truth.firstIndex(of: "new")! < truth.firstIndex(of: opp)! ? "new" : opp)
                s.advance()
                picks += 1
            }
            XCTAssertEqual(s.finalIds, truth, "insert at \(truePos)")
            XCTAssertLessThanOrEqual(picks, s.estimatedTotal)
        }
    }

    func testPickRecordsComparisonAndEloAndIgnoresDoublePick() {
        var s = RankSession(newId: "new", rankedIds: ["a", "b"], elo: ["a": 1500, "b": 1500])
        s.pick("new")
        s.pick("new")
        XCTAssertEqual(s.comparisons.count, 1)
        XCTAssertGreaterThan(s.elo["new"]!, 1500)
    }
}

final class TextRulesTests: XCTestCase {
    func testProfanityCatchesLeetspeakAndIgnoresClean() {
        XCTAssertNotNil(Profanity.check("sh1t movie"))
        XCTAssertNotNil(Profanity.check("F.U.C.K".replacingOccurrences(of: ".", with: "")))
        XCTAssertNil(Profanity.check("A masterpiece of genre-blending."))
    }

    func testUsernameRules() {
        XCTAssertEqual(Usernames.sanitize("Hello World_9!"), "helloworld_9")
        XCTAssertEqual(Usernames.localError("abc"), "At least 4 characters")
        XCTAssertNil(Usernames.localError("film_buff_22"))
    }

    func testTimeFormatting() {
        let now = Date()
        XCTAssertEqual(TimeFmt.relative(now.addingTimeInterval(-30), now: now), "just now")
        XCTAssertEqual(TimeFmt.relative(now.addingTimeInterval(-300), now: now), "5m ago")
        XCTAssertEqual(TimeFmt.relative(now.addingTimeInterval(-7200), now: now), "2h ago")
    }
}
