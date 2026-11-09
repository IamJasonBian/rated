import AVFoundation
import SwiftUI
import UIKit

/// Full-bleed muted video loop over its own poster frame. The poster is always
/// underneath, so a missing or failed video, or Reduce Motion, just leaves it showing.
struct LoopingVideoBackground: UIViewRepresentable {
    let video: String
    let poster: String

    func makeUIView(context: Context) -> LoopingVideoView {
        LoopingVideoView(video: video, poster: poster)
    }

    func updateUIView(_ uiView: LoopingVideoView, context: Context) {}

    static func dismantleUIView(_ uiView: LoopingVideoView, coordinator: ()) {
        uiView.tearDown()
    }
}

final class LoopingVideoView: UIView {
    private let video: String
    private let posterView = UIImageView()
    private let playerLayer = AVPlayerLayer()
    private var looper: AVPlayerLooper?
    private var statusObservations: [NSKeyValueObservation] = []
    private(set) var player: AVQueuePlayer?

    init(video: String, poster: String) {
        self.video = video
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false

        posterView.image = UIImage(named: poster)
        posterView.contentMode = .scaleAspectFill
        posterView.frame = bounds
        posterView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(posterView)

        // The layer draws nothing until it has a frame, so the poster shows through.
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(sync), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(sync), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(audioInterrupted), name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(mediaServicesReset), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        sync()
    }

    /// Brings playback in line with window, app state and Reduce Motion. Safe to call repeatedly.
    @objc func sync() {
        guard window != nil, !UIAccessibility.isReduceMotionEnabled else { tearDown(); return }
        guard UIApplication.shared.applicationState != .background else { player?.pause(); return }
        if player == nil { build() }
        player?.play()
    }

    /// Stops playback and releases the player; the poster remains.
    func tearDown() {
        statusObservations = []
        looper?.disableLooping()
        looper = nil
        player?.pause()
        player?.removeAllItems()
        player = nil
        playerLayer.player = nil
    }

    private func build() {
        guard let url = Bundle.main.url(forResource: video, withExtension: "mp4") else { return }

        // Never take the audio route or interrupt the user's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])

        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.allowsExternalPlayback = false
        queue.preventsDisplaySleepDuringVideoPlayback = false
        let loop = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(asset: AVURLAsset(url: url)))

        statusObservations = [
            queue.observe(\.status) { [weak self] p, _ in if p.status == .failed { self?.failed() } },
            loop.observe(\.status) { [weak self] l, _ in if l.status == .failed { self?.failed() } },
        ]
        player = queue
        looper = loop
        playerLayer.player = queue
    }

    /// KVO can fire on any queue. Falls back to the poster; the next foreground retries.
    private func failed() {
        DispatchQueue.main.async { [weak self] in self?.tearDown() }
    }

    @objc private func didEnterBackground() {
        player?.pause()
    }

    @objc private func audioInterrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
        DispatchQueue.main.async { [weak self] in self?.sync() }
    }

    @objc private func mediaServicesReset() {
        DispatchQueue.main.async { [weak self] in
            self?.tearDown()
            self?.sync()
        }
    }
}
