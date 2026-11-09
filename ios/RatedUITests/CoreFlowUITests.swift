import XCTest

/// End-to-end flows against a running backend (see ios/README.md). Each test
/// starts from a wiped install via `-uitest-reset`. They double as the
/// scripted walkthroughs recorded into docs/ios/gifs by scripts/record-gifs.sh.
/// Set RATED_SHOT_DIR to save a PNG of each named screen there.
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

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["RATED_SHOT_DIR"] else { return }
        pause(1.0)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

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

    private func assertOnMainTabs() {
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 8))
    }

    func test01_OnboardingAndPairwiseRanking() {
        signUp()
        XCTAssertTrue(app.staticTexts["onboarding-progress"].waitForExistence(timeout: 10))
        pause()
        shot("onboarding")
        for id in ["onboard-m-001", "onboard-m-003", "onboard-m-004"] { rank(id); pause(0.6) }
        XCTAssertTrue(app.staticTexts["3 / 5 RANKED"].waitForExistence(timeout: 5))
        pause()
        tap("onboarding-skip")
        assertOnMainTabs()
        pause(1.2)
    }

    func test02_DetailSaveAndReview() {
        signUp()
        tap("onboarding-skip", timeout: 10)
        assertOnMainTabs()
        pause(1.5)
        shot("home")
        tap("highlight-m-002")
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 8))
        pause(1.2)
        tap("detail-save")
        pause(0.6)
        shot("detail")
        tap("detail-review")
        tap("rating-9")
        let text = app.textViews["review-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 4))
        text.tap()
        text.typeText("Class satire that turns into a thriller without missing a beat.")
        pause(0.6)
        tap("review-submit")
        pause(2.0)
        app.tabBars.buttons["Profile"].tap()
        tap("tab-saved")
        XCTAssertTrue(app.staticTexts["SAVED · 1"].waitForExistence(timeout: 5))
        shot("profile-saved")
        tap("tab-reviews")
        XCTAssertTrue(app.staticTexts["1 REVIEWS · MOST RECENT FIRST"].waitForExistence(timeout: 5))
        shot("profile-reviews")
    }

    func test03_ProfileRankingsAndSettings() {
        signUp()
        XCTAssertTrue(app.staticTexts["onboarding-progress"].waitForExistence(timeout: 10))
        for id in ["onboard-m-001", "onboard-m-002", "onboard-m-003"] { rank(id) }
        tap("onboarding-skip")
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ranking-m-003"].firstMatch.waitForExistence(timeout: 5))
        shot("profile")
        tap("open-settings")
        shot("settings")
        tap("settings-account")
        XCTAssertTrue(app.textFields["display-name"].waitForExistence(timeout: 4))
        shot("settings-account")
        tap("save-profile")
        XCTAssertTrue(app.buttons["✓ SAVED"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()
        tap("settings-about")
        XCTAssertTrue(app.staticTexts["● reachable"].waitForExistence(timeout: 8))
        shot("settings-about")
        app.navigationBars.buttons.firstMatch.tap()
        tap("sign-out")
        XCTAssertTrue(app.buttons["login-apple"].waitForExistence(timeout: 5))
    }

    func test04_SearchAndLeaderboard() {
        signUp()
        tap("onboarding-skip", timeout: 10)
        app.tabBars.buttons["Search"].tap()
        shot("search")
        let f = app.textFields["search-field"]
        XCTAssertTrue(f.waitForExistence(timeout: 4))
        f.tap()
        f.typeText("interstellar\n")
        tap("result-m-001")
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Board"].tap()
        XCTAssertTrue(app.buttons["top-m-005"].waitForExistence(timeout: 8))
        shot("leaderboard")
    }

    /// Backend down: a restored session shows honest states instead of fake content.
    func test05_BackendUnreachable() {
        signUp()
        tap("onboarding-skip", timeout: 10)
        assertOnMainTabs()
        pause(1.5)
        app.terminate()
        app.launchArguments = ["-rated.apiBase", "http://127.0.0.1:9"]
        app.launch()
        assertOnMainTabs()
        XCTAssertTrue(app.staticTexts["Couldn't load movies"].waitForExistence(timeout: 20))
        shot("unreachable-home")
        app.tabBars.buttons["Board"].tap()
        XCTAssertTrue(app.staticTexts["Couldn't load the leaderboard"].waitForExistence(timeout: 20))
        shot("unreachable-board")
        app.tabBars.buttons["Search"].tap()
        let f = app.textFields["search-field"]
        XCTAssertTrue(f.waitForExistence(timeout: 4))
        f.tap()
        f.typeText("alien\n")
        XCTAssertTrue(app.staticTexts["Couldn't search right now"].waitForExistence(timeout: 20))
        shot("unreachable-search")
    }
}
