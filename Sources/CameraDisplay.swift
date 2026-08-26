import AVFoundation
import AVKit
import OSLog
import SwiftUI
import UIKit

/// Provides the private camera capture source and hands a blank helper view to Picture-in-Picture
/// when the app is minimized. The front-camera image is never displayed to the user.
///
/// Why this isn't an `AVCaptureVideoPreviewLayer`: iOS shuts the camera off the moment an app is
/// backgrounded, so "detect while I'm in another app" is impossible — with one exception. If the
/// app stays visible in a PiP window it counts as still on screen, and (iOS 18+, with the `voip`
/// background mode) the capture session is allowed to keep running. PiP can only carry an
/// `AVSampleBufferDisplayLayer`, so frames are rendered by hand into one.
///
/// The floating window itself is not this layer, though: it's a `PipWindowController` — a blank
/// rectangle, sized by `preferredContentSize`, which is the only lever AVKit gives us on how much of
/// the screen the window takes. Nothing is drawn in it and no frames go to it. The one reaction that
/// still lands there is the buzz at three seconds; the red frame and the blur belong to the open app,
/// which can't paint over the rest of the phone anyway.
@MainActor
final class CameraDisplay: NSObject, ObservableObject {

    let layer = AVSampleBufferDisplayLayer()

    /// True while the app is showing as a floating PiP window over another app.
    @Published private(set) var isPictureInPictureActive = false {
        didSet { pipLock.withLock { pipActive = isPictureInPictureActive } }
    }

    /// True while the PiP window is *stashed* — swiped into the screen edge, where only a small
    /// chevron of it remains. iOS treats that as the app having nothing on screen, so it revokes
    /// camera access; see `evaluateSuspension()`, which is what pulls the window back out.
    @Published private(set) var isStashed = false {
        didSet { onStashChange?(isStashed) }
    }

    /// Called on the main thread whenever the window is stashed or comes back, so the detector can
    /// stop and restart the capture session around the gap.
    var onStashChange: ((Bool) -> Void)?

    /// Called on the main thread with the size the floating window actually got. We only ask for a
    /// ratio, so this is what says whether asking for thinner did anything; the HUD shows it.
    var onWindowSizeChange: ((CGSize) -> Void)?

    /// How thick the thread is drawn. The one number that decides whether the bar reads as a hairline
    /// or as something you can see across the room — and, since its touches belong to iOS, how easy
    /// it is to hit by accident.
    var windowThickness = PipWindow.savedThickness {
        didSet {
            guard windowThickness != oldValue else { return }
            PipWindow.savedThickness = windowThickness
            applyWindowSize()
        }
    }

    /// The same flag, readable from the capture queue — the detector checks it to decide whether
    /// a reaction belongs to the PiP window (darken + buzz) or to the open app (blur).
    nonisolated var isInPictureInPicture: Bool { pipLock.withLock { pipActive } }
    private nonisolated let pipLock = NSLock()
    private nonisolated(unsafe) var pipActive = false
    /// The colour the window is currently showing, so repeat frames cost nothing.
    private nonisolated(unsafe) var shownTint: PipWindow.Tint?

    private var pipController: AVPictureInPictureController?
    private var pipContent: PipWindowController?

    // MARK: Stash handling
    private var stashPolicy = StashPolicy()
    private var suspensionObservation: NSKeyValueObservation?
    private var suspensionTimer: Timer?
    /// Set while a stop→start restart is in flight, so the stop isn't mistaken for the user
    /// closing the window.
    private var restartingPictureInPicture = false
    /// Held while the window is stashed, so the app is allowed to keep running long enough to get it
    /// back out — see `beginStashAssertion()`.
    private var stashAssertion: UIBackgroundTaskIdentifier = .invalid
    private var decodeObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "com.awaira.ios", category: "pip")

    override init() {
        super.init()
        layer.videoGravity = .resizeAspectFill
        // Selfie view. PiP shows the buffers themselves, so its window is unmirrored — only the
        // in-app preview is flipped, which is where mirroring actually helps.
        layer.transform = CATransform3DMakeScale(-1, 1, 1)
        // Diagnostics only — the recovery itself happens in `enqueue`, which checks the renderer
        // before every frame. Flushing straight from this notification would just fail again while
        // decoder resources are still off-limits.
        decodeObserver = NotificationCenter.default.addObserver(
            forName: AVSampleBufferVideoRenderer.didFailToDecodeNotification,
            object: layer.sampleBufferRenderer, queue: .main) { [weak self] note in
                let error = note.userInfo?[AVSampleBufferVideoRenderer.didFailToDecodeNotificationErrorKey]
                Task { @MainActor in
                    self?.log.error("renderer failed to decode: \(String(describing: error), privacy: .public)")
                }
            }
    }

    /// Wire up PiP once the preview is on screen. Safe to call repeatedly.
    ///
    /// The window it opens is a `PipWindowController` — a blank rectangle sized by
    /// `preferredContentSize`, which is the only way to tell AVKit how big the window should be.
    func preparePictureInPicture(sourceView: UIView) {
        guard pipController == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        // A mixing playback session — PiP requires an audio-capable session, and mixing means we
        // never interrupt whatever the user is listening to.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback,
                                                         options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let content = PipWindowController()
        content.preferredContentSize = PipWindow.preferredSize(thickness: windowThickness)
        content.onSizeChange = { [weak self] size in self?.onWindowSizeChange?(size) }
        let source = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: sourceView,
                                                                contentViewController: content)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        // This is the whole point: minimizing the app slides it into PiP instead of suspending it.
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pipController = controller
        pipContent = content
    }

    /// Colour the floating window for the current detection level — the window is the only thing the
    /// app can show while the user is in another app, so it stands in for the red frame. Called on
    /// every processed frame from the capture queue, and does nothing until the colour actually
    /// changes.
    nonisolated func showLevel(_ level: Int) {
        let tint = PipWindow.tint(forLevel: level)
        let changed = pipLock.withLock { () -> Bool in
            guard shownTint != tint else { return false }
            shownTint = tint
            return true
        }
        guard changed else { return }
        Task { @MainActor in
            self.pipContent?.view.backgroundColor = PipWindow.colour(for: tint)
        }
    }

    /// Show one camera frame. Only the in-app preview needs frames — the floating window draws
    /// itself, so while it's up the detector stops calling this entirely.
    nonisolated func enqueue(_ sampleBuffer: CMSampleBuffer) {
        Task { @MainActor in
            self.prepareRenderer().enqueue(sampleBuffer)
        }
    }

    /// The renderer, reset if it can't accept frames. `requiresFlushToResumeDecoding` is how it
    /// reports that the app was in a state where video decoding wasn't permitted — being minimized is
    /// exactly such a state — and until it's flushed every enqueue is silently dropped, which is what
    /// would leave the preview frozen when the app comes back.
    private func prepareRenderer() -> AVSampleBufferVideoRenderer {
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding { renderer.flush() }
        return renderer
    }

    /// Reset the renderer so the next frame is displayed rather than dropped. Called when capture
    /// resumes — waiting for the next frame to notice would cost time.
    /// `nonisolated` because the detector calls it from whichever thread told it capture is back.
    nonisolated func flushRenderer() {
        Task { @MainActor in _ = self.prepareRenderer() }
    }

    // MARK: - Window size

    /// Push the current choice at the window. Whether AVKit resizes a window that is already up is
    /// undocumented; if it doesn't, the size still lands the next time PiP opens — which is the usual
    /// case anyway, since the settings panel is only reachable with the app open.
    private func applyWindowSize() {
        pipContent?.preferredContentSize = PipWindow.preferredSize(thickness: windowThickness)
    }

    // MARK: - Stash (the window swiped into the screen edge)

    /// Watch for the window being stashed. Two signals for one job: KVO reacts within a frame, and
    /// the poll both covers the case where `isPictureInPictureSuspended` isn't KVO-compliant (AVKit
    /// doesn't document it as observable) and drives the follow-up attempts `StashPolicy` needs.
    private func startWatchingSuspension() {
        guard let controller = pipController else { return }
        suspensionObservation = controller.observe(\.isPictureInPictureSuspended,
                                                    options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.evaluateSuspension() }
        }
        suspensionTimer?.invalidate()
        // Fast, because every tick the window spends in the wall is a tick with no camera.
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateSuspension() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        suspensionTimer = timer
    }

    private func stopWatchingSuspension() {
        suspensionObservation = nil
        suspensionTimer?.invalidate()
        suspensionTimer = nil
        stashPolicy.reset()
        endStashAssertion()
        if isStashed { isStashed = false }
    }

    /// Keep the app running while the window is in the wall.
    ///
    /// With the camera revoked and no pixels on screen there is nothing else holding the process up,
    /// and a suspended process can't run the timer that gets the window back — which is why the
    /// window used to stay there for good. The assertion is short-lived by design: iOS ends it after
    /// a while, and by then either the window is out or it isn't coming out.
    private func beginStashAssertion() {
        guard stashAssertion == .invalid else { return }
        stashAssertion = UIApplication.shared.beginBackgroundTask(withName: "awaira.pip.stash") {
            [weak self] in
            Task { @MainActor in self?.endStashAssertion() }
        }
    }

    private func endStashAssertion() {
        guard stashAssertion != .invalid else { return }
        UIApplication.shared.endBackgroundTask(stashAssertion)
        stashAssertion = .invalid
    }

    /// Idempotent: tracks the stash flag and, while stashed, asks `StashPolicy` what to try next.
    ///
    /// Deliberately not conditioned on `isPictureInPictureActive`: a window deep enough in the wall
    /// stops counting as active, and that is exactly the state we have to dig out of. Requiring
    /// "active" here is what once left a grey stub in the edge with the camera off and nothing
    /// trying to bring it back.
    private func evaluateSuspension() {
        guard let controller = pipController else { return }
        let suspended = controller.isPictureInPictureSuspended
        if suspended != isStashed {
            log.info("pip stashed: \(suspended, privacy: .public)")
            if !suspended { stashPolicy.reset() }
            isStashed = suspended
        }
        guard suspended else {
            endStashAssertion()
            return
        }
        // The whole reason a stashed window used to stay stashed: the moment iOS takes the camera
        // away, the app has nothing left keeping it alive, so the process is frozen — and frozen code
        // cannot pull anything out of anywhere. This assertion buys the seconds the rescue needs.
        beginStashAssertion()

        switch stashPolicy.actionOnSuspend(at: CACurrentMediaTime()) {
        case .soft:
            log.info("lifting stash: start on the active controller")
            controller.startPictureInPicture()
        case .restart:
            log.info("lifting stash: restarting picture in picture")
            restartPictureInPicture(controller)
        case .wait:
            break
        }
    }

    /// The heavier way back: stop PiP and start it again. Stopping is what lets the window return
    /// unstashed, but with nothing of the app on screen iOS could suspend the process in the gap —
    /// hence the background-task assertion around it. The restart itself happens in the delegate's
    /// `didStop`, which is the first moment PiP is willing to start again.
    private func restartPictureInPicture(_ controller: AVPictureInPictureController) {
        let assertion = UIApplication.shared.beginBackgroundTask(withName: "awaira.pip.restore")
        restartingPictureInPicture = true
        controller.stopPictureInPicture()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion) }
        }
    }
}

// MARK: - PiP plumbing

/// `@preconcurrency` on the conformance, not on each method: `CameraDisplay` is `@MainActor`, while
/// AVKit still declares these delegate methods without isolation, so every one of them reads as
/// crossing into the main actor. AVKit does call them on the main thread — the attribute states that
/// assumption once and has the compiler insert the runtime check for it, instead of scattering
/// `MainActor.assumeIsolated` through five callbacks.
extension CameraDisplay: @preconcurrency AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        isPictureInPictureActive = true
        restartingPictureInPicture = false
        // Forget the colour: the next frame should paint the window for what's happening now, even if
        // that's the same level the app was minimized on.
        pipLock.withLock { shownTint = nil }
        startWatchingSuspension()
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        // A stop we asked for, to shake the window out of the edge: start again straight away and
        // leave `isPictureInPictureActive` alone, so the detector never sees a false "app is open".
        if restartingPictureInPicture {
            restartingPictureInPicture = false
            controller.startPictureInPicture()
            return
        }
        // A window that stops while still suspended didn't stop because the user closed it or came
        // back to the app — it sank into the screen edge far enough for AVKit to drop it. Left alone
        // that is the dead end: a grey stub in the wall, the camera gone, and nobody watching any
        // more, because giving up the observation here is what makes it permanent. So keep watching
        // and start it again.
        if controller.isPictureInPictureSuspended, UIApplication.shared.applicationState != .active {
            log.notice("pip stopped while stashed; restarting it")
            controller.startPictureInPicture()
            return
        }
        isPictureInPictureActive = false
        stopWatchingSuspension()
    }

    /// A tap on the thread is iOS asking the app to come back to full screen. It isn't a control —
    /// it's a line of colour that must not be worth touching — so the restore is refused: reporting
    /// failure leaves the window where it is instead of throwing the user into the app. The tap
    /// itself belongs to the system window and can't be blocked; this is the answer to it.
    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler
                                    completionHandler: @escaping (Bool) -> Void) {
        log.info("refusing to restore from a tap on the thread")
        completionHandler(false)
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        log.error("picture in picture failed to start: \(error.localizedDescription, privacy: .public)")
        restartingPictureInPicture = false
        isPictureInPictureActive = false
        stopWatchingSuspension()
    }
}

/// Hosts the PiP source view. `showsVideo` exists for internal diagnostics only; normal Awaira
/// use passes `false`, so the front-camera image is never drawn on screen.
struct CameraDisplayView: UIViewRepresentable {
    let display: CameraDisplay
    var showsVideo = false

    func makeUIView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.backgroundColor = .clear
        if showsVideo {
            view.hosted = display.layer
            view.layer.addSublayer(display.layer)
        }
        display.preparePictureInPicture(sourceView: view)
        return view
    }

    func updateUIView(_ uiView: LayerHostView, context: Context) { }

    final class LayerHostView: UIView {
        var hosted: CALayer?

        override func layoutSubviews() {
            super.layoutSubviews()
            // The layer is driven manually, so it doesn't get autoresized for free.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hosted?.frame = bounds
            CATransaction.commit()
        }
    }
}
