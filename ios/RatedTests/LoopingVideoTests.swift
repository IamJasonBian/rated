import AVFoundation
import XCTest
@testable import Rated

/// Drives the player lifecycle paths a simulator can't trigger on demand.
final class LoopingVideoTests: XCTestCase {
    private func onScreenView(video: String = "login-loop") -> (LoopingVideoView, UIWindow) {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let view = LoopingVideoView(video: video, poster: "login-poster.jpg")
        window.addSubview(view)
        window.isHidden = false
        return (view, window)
    }

    private func drainMain() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }

    func testBundleCarriesAssets() {
        XCTAssertNotNil(Bundle.main.url(forResource: "login-loop", withExtension: "mp4"))
        XCTAssertNotNil(UIImage(named: "login-poster.jpg"))
    }

    func testPlaysMutedOnceInWindow() throws {
        let (view, window) = onScreenView()
        _ = window
        let player = try XCTUnwrap(view.player)
        XCTAssertTrue(player.isMuted)
        XCTAssertEqual(player.rate, 1)
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .ambient)
    }

    func testBackgroundPausesAndForegroundResumes() throws {
        let (view, window) = onScreenView()
        _ = window
        let player = try XCTUnwrap(view.player)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(player.rate, 0)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(player.rate, 1)
    }

    func testResumesWhenInterruptionEnds() throws {
        let (view, window) = onScreenView()
        _ = window
        let player = try XCTUnwrap(view.player)
        player.pause()
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        drainMain()
        XCTAssertEqual(player.rate, 1)
    }

    func testMediaServicesResetRebuildsPlayer() throws {
        let (view, window) = onScreenView()
        _ = window
        let before = try XCTUnwrap(view.player)
        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        drainMain()
        XCTAssertNotNil(view.player)
        XCTAssertFalse(view.player === before)
    }

    func testRemovalFromWindowTearsDown() {
        let (view, window) = onScreenView()
        _ = window
        XCTAssertNotNil(view.player)
        view.removeFromSuperview()
        XCTAssertNil(view.player)
    }

    func testMissingAssetLeavesPosterOnly() {
        let (view, window) = onScreenView(video: "no-such-clip")
        _ = window
        XCTAssertNil(view.player)
    }
}
