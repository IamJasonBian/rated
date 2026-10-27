import XCTest

/// End-to-end flows against a running backend (see ios/README.md). Each test
/// starts from a wiped install via `-uitest-reset`. They double as the
/// scripted walkthroughs recorded into docs/ios/gifs by scripts/record-gifs.sh.
final class CoreFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
        if let base = ProcessInfo.processInfo.environment["RATED_API_BASE"] { app.launchArguments += ["-rated.apiBase", base] }
        app.launch()
    }

    private func pause(_ s: Double = 0.8) { Thread.sleep(forTimeInterval: s) }

    /// Typed queries first — `descendants(matching: .any)` can time out on busy feeds.
    private func tap(_ id: String, timeout: Double = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        let typed = [app.buttons[id], app.staticTexts[id], app.textFields[id], app.otherElements[id]].map(\.firstMatch)
        repeat {
            if let el = typed.first(where: \.exists) { el.tap(); return }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        let el = app.descendants(matching: .any)[id].firstMatch
        XCTAssertTrue(el.waitForExistence(timeout: 2), "missing \(id)")
        el.tap()
    }

    /// Sign in → name → @handle. Uses a per-run handle so reruns don't collide server-side.
    private func signUp(name: String = "Jason") {
        tap("login-apple")
        let nameField = app.textFields["name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText(name)
        pause(0.4)
        tap("name-continue")
        let u = app.textFields["username-field"]
        XCTAssertTrue(u.waitForExistence(timeout: 5))
        u.tap()
        u.typeText("ios\(Int(Date().timeIntervalSince1970) % 1_000_000)")
        pause(1.2)
        tap("username-claim")
    }

    /// Rank `id` by always preferring the new movie (lands it at #1).
    private func rank(_ id: String) {
        tap(id)
        while app.buttons["rank-pick-new"].waitForExistence(timeout: 2) {
            pause(0.5)
            app.buttons["rank-pick-new"].tap()
            pause(0.6)
            tap("rank-next")
        }
        XCTAssertTrue(app.staticTexts["rank-landed"].waitForExistence(timeout: 5))
        pause(1.0)
        tap("rank-save")
    }

    func test01_OnboardingAndPairwiseRanking() {
        signUp()
        XCTAssertTrue(app.staticTexts["onboarding-progress"].waitForExistence(timeout: 10))
        pause()
        for id in ["onboard-m-001", "onboard-m-003", "onboard-m-004"] { rank(id); pause(0.6) }
        XCTAssertTrue(app.staticTexts["3 / 5 RANKED"].waitForExistence(timeout: 5))
        pause()
        tap("onboarding-skip")
        XCTAssertTrue(app.buttons["bell"].waitForExistence(timeout: 8))
        pause(1.2)
    }

    func test02_FeedLikeReplyAndDetail() {
        signUp()
        tap("onboarding-skip", timeout: 10)
        XCTAssertTrue(app.buttons["bell"].waitForExistence(timeout: 8))
        pause(1.5)
        tap("like-f-002")
        pause()
        tap("reply-f-002")
        let field = app.textFields["reply-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        field.typeText("Totally agree — the staircase scene!\n")
        pause(1.2)
        tap("highlight-m-002")
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 8))
        pause(1.2)
        app.swipeUp()
        pause(0.8)
        tap("detail-save")
        pause(0.6)
        tap("detail-review")
        tap("rating-9")
        let text = app.textViews["review-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 4))
        text.tap()
        text.typeText("Class satire that turns into a thriller without missing a beat.")
        pause(0.6)
        tap("review-submit")
        pause(2.0)
    }

    func test03_ProfileReorderAndSettings() {
        signUp()
        XCTAssertTrue(app.staticTexts["onboarding-progress"].waitForExistence(timeout: 10))
        for id in ["onboard-m-001", "onboard-m-002", "onboard-m-003"] { rank(id) }
        tap("onboarding-skip")
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["streak"].firstMatch.waitForExistence(timeout: 5))
        pause(1.2)
        tap("edit-rankings")
        pause(1.0)
        tap("edit-rankings")
        pause(0.6)
        tap("stat-following")
        pause(1.5)
        app.swipeDown(velocity: .fast)
        pause(0.6)
        tap("open-settings")
        tap("settings-appearance")
        pause(0.6)
        app.segmentedControls.buttons["Light"].tap()
        pause(1.5)
        app.segmentedControls.buttons["Dark"].tap()
        pause(1.0)
    }

    /// Requires the ticket-affiliate backend: follow @cinephile99 (seeded as a
    /// Parasite rater), rank Parasite, and the Buy tickets CTA appears.
    func test05_BuyTicketsCTA() {
        signUp()
        XCTAssertTrue(app.staticTexts["onboarding-progress"].waitForExistence(timeout: 10))
        rank("onboard-m-002")
        tap("onboarding-skip")
        app.tabBars.buttons["Search"].tap()
        tap("tab-users")
        let f = app.textFields["search-field"]
        XCTAssertTrue(f.waitForExistence(timeout: 4))
        f.tap()
        f.typeText("cine\n")
        pause(1.2)
        tap("follow-@cinephile99")
        pause(1.0)
        app.tabBars.buttons["Home"].tap()
        tap("highlight-m-002")
        XCTAssertTrue(app.buttons["buy-tickets"].waitForExistence(timeout: 8))
        pause(2.0)
    }

    func test04_UpcomingSearchLeaderboard() {
        signUp()
        tap("onboarding-skip", timeout: 10)
        app.tabBars.buttons["Upcoming"].tap()
        pause(1.0)
        tap("watchlist-u-002")
        pause(0.8)
        app.swipeUp()
        pause(0.6)
        app.tabBars.buttons["Search"].tap()
        let f = app.textFields["search-field"]
        XCTAssertTrue(f.waitForExistence(timeout: 4))
        f.tap()
        f.typeText("nolan\n")
        pause(1.5)
        app.tabBars.buttons["Board"].tap()
        pause(1.2)
        tap("tab-friends")
        pause(1.2)
        tap("tab-global")
        pause(0.8)
    }
}
