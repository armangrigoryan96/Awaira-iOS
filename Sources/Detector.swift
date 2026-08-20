import Foundation
import AVFoundation
import OSLog
import Vision
import UIKit
import QuartzCore

/// Camera + Vision on the iPhone's front camera, feeding `DetectionCore`.
///
/// This type deliberately holds no detection logic of its own: it owns the capture session, runs
/// the two Vision requests, converts their output into normalized display coordinates, and hands
/// the result to the core. Everything that decides *whether a hand is on the face* lives in
/// `DetectionCore` so it can be tested without a camera.
///
/// Threading: all detection state is touched only on `captureQueue` (serial), so it needs no
/// locking. `@Published` state is mutated only on the main thread, via `onMain`.
final class Detector: NSObject, ObservableObject {

    // MARK: Published UI state
    @Published var zone: [Double]?            // normalized head zone [x0,y0,x1,y1], display space
    @Published var hands: [[CGPoint]] = []    // normalized hand points, display space
    @Published var touching = false
    /// 0 = away, 1 = touching (red frame; PiP window darkens), 2 = lingering,
    /// 3 = sustained (blur when the app is open, a buzz when it's in PiP).
    @Published var touchLevel = 0
    @Published var count = 0                  // today's detections
    @Published private(set) var preventedPulls = 0
    @Published private(set) var actualPulls = 0
    @Published private(set) var activeSecondsToday = 0.0
    @Published private(set) var week: [MobileStatsStore.DayBar] = []
    @Published private(set) var hourOfWeek = Array(repeating: 0, count: 24)
    @Published private(set) var weeklyTotal = 0
    @Published private(set) var weeklyRate = 0.0
    @Published private(set) var weeklyImprovement: Double?
    @Published private(set) var lastDetection: Date?
    @Published var fps = 0.0
    @Published var hasFace = false
    @Published var connected = false          // camera running and delivering frames
    /// True while the PiP window sits stashed in the screen edge. iOS forbids capture when nothing
    /// of the app is on screen, so detection is paused for as long as this is true — the app tries
    /// to pull the window back out, see `CameraDisplay.evaluateSuspension()`.
    @Published private(set) var stashed = false
    /// The size the floating window actually got, once it has been up. We only ask AVKit for a
    /// ratio, so this is the only place the real height shows — the HUD prints it, since logs off
    /// the device need root. Nil until the app has been minimized at least once, and kept afterwards.
    @Published private(set) var pipWindowSize: CGSize?
    /// How many times the window has gone into the screen edge, and how many of those it came back
    /// from. Shown in the HUD because these two numbers are the only way to tell the three cases
    /// apart from outside: never noticed (0 seen), noticed but stuck (seen > back), or working
    /// (seen == back). Logs off the device need root, so this is the instrument.
    @Published private(set) var stashSeen = 0
    @Published private(set) var stashRecovered = 0
    @Published var errorText: String?
    /// Width / height of the camera buffer, so the overlay can undo the preview's aspect fill.
    @Published var bufferAspect: CGFloat = 3.0 / 4.0
    /// How thick the floating thread is — the only sizing choice the app exposes.
    @Published var pipThickness = PipWindow.savedThickness {
        didSet {
            let thickness = pipThickness
            Task { @MainActor in self.display.windowThickness = thickness }
        }
    }

    // MARK: Live-tunable settings (read on the capture queue, written from the UI)
    var level2After: TimeInterval {
        get { lock.withLock { core.config.level2After } }
        set { lock.withLock { core.config.level2After = newValue } }
    }
    var level3After: TimeInterval {
        get { lock.withLock { core.config.level3After } }
        set { lock.withLock { core.config.level3After = newValue } }
    }
    var zoneMultiplier: Double {
        get { lock.withLock { core.config.zoneMultiplier } }
        set { lock.withLock { core.config.zoneMultiplier = newValue } }
    }
    /// The three "when a hand lingers" cues the user can switch on independently. Read on the
    /// capture queue (where the level is decided) and written from the main thread, so they take the
    /// same lock as the detection config. Blur is handled in the view layer, not here.
    var vibrateEnabled: Bool {
        get { lock.withLock { vibrateEnabledFlag } }
        set { lock.withLock { vibrateEnabledFlag = newValue } }
    }
    var voiceEnabled: Bool {
        get { lock.withLock { voiceEnabledFlag } }
        set { lock.withLock { voiceEnabledFlag = newValue } }
    }

    /// The core is read on the capture queue and its config is written from the main thread, so
    /// unlike the rest of the detection state it does need the lock.
    private var core = DetectionCore()
    private let lock = NSLock()
    private var vibrateEnabledFlag = true
    private var voiceEnabledFlag = false
    private var pausedFlag = false
    private var backgrounded = false
    /// True once the session is allowed to keep capturing while the app is off-screen — i.e. in
    /// Picture-in-Picture. Without it, backgrounding must stop the camera.
    private var multitaskingAllowed = false

    /// Where frames are drawn, and what carries them into the PiP window.
    let display: CameraDisplay

    // MARK: Capture + Vision (configured/used only on captureQueue)
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "com.awaira.capture")
    private var started = false

    // Adaptive throughput. Detecting "a hand near the face" needs neither high resolution nor
    // 30 fps, and sustained full load just heats the phone until it thermally throttles. We cap
    // the hardware frame rate so CoreMedia only wakes up at our target rate; the software
    // throttle below is a safety net for formats that can't be capped.
    private var targetFPS: Double = 5.0
    private var targetFrameInterval: CFTimeInterval { 1.0 / targetFPS }
    private var lastProcessedTime: CFTimeInterval = 0
    private weak var captureDevice: AVCaptureDevice?

    // MARK: detection bookkeeping (capture queue only)
    private var frameIdx = 0
    private var lastFrameTime: CFTimeInterval = 0
    private var emaFps = 0.0
    private var todayKey = Detector.isoDay(Date())
    /// The last escalation level, kept on the capture queue so undetected frames still know
    /// whether the lingering effect should be burned into them.
    private var lastLevel = 0
    private var lastStatsPublish: CFTimeInterval = 0
    /// Aggregate-only, local history backing the mobile dashboard.
    private let stats = MobileStatsStore()

    /// Run the face request every Nth frame, as on the Mac.
    private let faceEvery = 3

    private let log = Logger(subsystem: "com.awaira.ios", category: "capture")

    // MARK: Vision requests (reused across frames)
    private let faceRequest = VNDetectFaceRectanglesRequest()
    private let handRequest: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()

    /// Main-actor because it builds the display layer; the detector is created from the UI.
    @MainActor override init() {
        display = CameraDisplay()
        super.init()
        applyStats(stats.snapshot())
        updateQualityForThermalState()
        // Swiping the floating window into the screen edge takes the app off screen entirely, which
        // iOS answers by cutting the camera. The window is pulled back out for us; this is where we
        // pick the capture session back up once it is.
        display.onStashChange = { [weak self] stashed in self?.stashChanged(to: stashed) }
        display.onWindowSizeChange = { [weak self] size in
            self?.onMain { self?.pipWindowSize = size }
        }
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(thermalStateChanged),
                       name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        // The camera must be off while the app is in the background — iOS would suspend it
        // anyway, but stopping it ourselves clears the live state instead of freezing it.
        nc.addObserver(self, selector: #selector(appDidEnterBackground),
                       name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(appWillEnterForeground),
                       name: UIApplication.willEnterForegroundNotification, object: nil)
        // Calls, Siri, Split View, a hardware pressure event — the session tells us either way.
        nc.addObserver(self, selector: #selector(sessionWasInterrupted(_:)),
                       name: AVCaptureSession.wasInterruptedNotification, object: session)
        nc.addObserver(self, selector: #selector(sessionInterruptionEnded),
                       name: AVCaptureSession.interruptionEndedNotification, object: session)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Lifecycle

    /// Request camera access (if needed) and start capture. Safe to call repeatedly.
    func start() {
        guard !started else { return }
        started = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            beginSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted { self.beginSession() }
                else { self.fail("Awaira needs the camera. Enable it in Settings → Privacy & Security → Camera.") }
            }
        default:
            fail("Camera access is denied. Enable it in Settings → Privacy & Security → Camera.")
        }
    }

    /// Fully stop capture and clear live state.
    func stop() {
        guard started else { return }
        started = false
        captureQueue.async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            self.core.reset()
        }
        clearLiveState()
    }

    func togglePause() {
        let nowPaused = lock.withLock { pausedFlag.toggle(); return pausedFlag }
        captureQueue.async { [weak self] in
            guard let self else { return }
            if nowPaused { self.session.stopRunning(); self.core.reset() }
            else if !self.lock.withLock({ self.backgrounded }) { self.session.startRunning() }
        }
        if nowPaused { clearLiveState() }
    }

    var isPaused: Bool { lock.withLock { pausedFlag } }

    private func fail(_ message: String) {
        onMain {
            self.errorText = message
            self.connected = false
        }
    }

    private func clearLiveState() {
        // Whatever stopped detection — a pause, the window being stashed, a call coming in — we can no
        // longer tell whether the hand is still there, so the cues must not outlive it.
        Haptics.stopSustained()
        CalmingTone.stopSustained()
        onMain {
            self.touching = false
            self.hasFace = false
            self.touchLevel = 0
            self.zone = nil
            self.hands = []
            self.connected = false
        }
    }

    private func beginSession() {
        captureQueue.async { [weak self] in self?.configureAndRun() }
    }

    /// Build the capture session. Every step is guarded — a failure surfaces as `errorText`.
    private func configureAndRun() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video) else {
            fail("No camera was found on this iPhone.")
            return
        }
        session.beginConfiguration()
        // Vision handles face/hand detection fine at VGA, and the smaller the buffer the less
        // heat we make. (The Mac uses .low = 320×240; on the iPhone's much wider front-camera
        // field of view that leaves the face too small, so VGA is the equivalent choice.)
        if session.canSetSessionPreset(.vga640x480)  { session.sessionPreset = .vga640x480 }
        else if session.canSetSessionPreset(.medium) { session.sessionPreset = .medium }
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            session.commitConfiguration()
            fail("Could not open the camera.")
            return
        }
        session.addInput(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            fail("Could not attach the camera output.")
            return
        }
        session.addOutput(output)
        // Rotate the buffer to portrait-upright and leave it unmirrored, which is exactly what
        // the Mac's webcam delivers — so `orientation: .up` and the mirroring inside
        // `displayRect` mean the same thing on both platforms. The app is portrait-locked.
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
        // Keep capturing while the app is a floating PiP window. This is the one path iOS 18+
        // allows a camera to survive the user leaving the app, and it depends on the `voip`
        // background mode declared in project.yml.
        if session.isMultitaskingCameraAccessSupported {
            session.isMultitaskingCameraAccessEnabled = true
            lock.withLock { multitaskingAllowed = true }
        }
        session.commitConfiguration()
        // Cap the hardware frame rate now that the format is locked in, so CoreMedia only wakes
        // up at our detection rate instead of 30fps — the dominant energy cost.
        captureDevice = device
        applyHardwareFrameRate(targetFPS)
        session.startRunning()
    }

    // MARK: - Thermals

    @objc private func thermalStateChanged() {
        captureQueue.async { self.updateQualityForThermalState() }
    }

    /// Lower the processed frame rate as the phone heats up; restore it as it cools.
    private func updateQualityForThermalState() {
        let fps: Double
        switch ProcessInfo.processInfo.thermalState {
        case .nominal, .fair: fps = 5.0
        case .serious:        fps = 4.0
        case .critical:       fps = 3.0
        @unknown default:     fps = 5.0
        }
        targetFPS = fps
        applyHardwareFrameRate(fps)
    }

    private func applyHardwareFrameRate(_ fps: Double) {
        guard let device = captureDevice else { return }
        let duration = CMTimeMakeWithSeconds(1.0 / fps, preferredTimescale: 600)
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        guard let range = ranges.first, Double(range.minFrameRate) <= fps else { return }
        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch { }
    }

    // MARK: - Background / interruption

    @objc private func appDidEnterBackground() {
        guard started else { return }
        // In PiP the app is off-screen but still capturing — that's the whole point, so keep
        // detecting and leave `backgrounded` false so `process()` isn't gated off.
        if lock.withLock({ multitaskingAllowed }) { return }
        let didSuspend = lock.withLock { () -> Bool in
            guard !backgrounded else { return false }
            backgrounded = true
            return true
        }
        guard didSuspend else { return }
        captureQueue.async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            self.core.reset()
        }
        clearLiveState()
    }

    @objc private func appWillEnterForeground() {
        let shouldResume = lock.withLock { () -> Bool in
            guard backgrounded else { return false }
            backgrounded = false
            return !pausedFlag
        }
        guard shouldResume, started else { return }
        captureQueue.async { [weak self] in self?.session.startRunning() }
    }

    /// A stashed PiP window arrives here as reason 1, `videoDeviceNotAvailableInBackground` — the
    /// one interruption `isMultitaskingCameraAccessEnabled` does *not* shield us from, because it
    /// isn't about sharing the camera, it's about the app having no pixels on screen. Not an error
    /// to show the user: iOS preserves the `startRunning` request, and the window is on its way
    /// back out of the edge anyway.
    @objc private func sessionWasInterrupted(_ note: Notification) {
        let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)
            .flatMap { AVCaptureSession.InterruptionReason(rawValue: $0.intValue) }
        log.info("capture interrupted, reason \(reason?.rawValue ?? -1, privacy: .public)")
        captureQueue.async { [weak self] in self?.core.reset() }
        clearLiveState()
    }

    @objc private func sessionInterruptionEnded() {
        log.info("capture interruption ended")
        resumeCapture()
    }

    /// The window went into the edge (or came back out of it).
    private func stashChanged(to isStashed: Bool) {
        onMain {
            self.stashed = isStashed
            if isStashed { self.stashSeen += 1 } else if self.stashSeen > 0 { self.stashRecovered += 1 }
        }
        if isStashed {
            // Capture is already gone or about to be; drop the stale detection state so a hand held
            // through the gap can't be read as one long touch, and clear the last frame's counters.
            captureQueue.async { [weak self] in self?.core.reset() }
            clearLiveState()
        } else {
            resumeCapture()
        }
    }

    /// Bring capture back after a stash or an interruption. Idempotent, and reached from both the
    /// un-stash callback and `AVCaptureSessionInterruptionEnded` — whichever lands first — because
    /// waiting only on the notification can leave the window live with a dead camera.
    private func resumeCapture() {
        guard started, !lock.withLock({ pausedFlag || backgrounded }) else { return }
        display.flushRenderer()
        captureQueue.async { [weak self] in
            guard let self else { return }
            self.core.reset()
            self.lastLevel = 0
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    // MARK: - Helpers

    private func onMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread { body() } else { DispatchQueue.main.async(execute: body) }
    }

    private static func isoDay(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// At local midnight, today's counter starts again at zero.
    private func rollDayIfNeeded() {
        let key = Self.isoDay(Date())
        guard key != todayKey else { return }
        todayKey = key
        let snapshot = stats.snapshot()
        onMain { self.applyStats(snapshot) }
    }

    private func applyStats(_ snapshot: MobileStatsStore.Snapshot) {
        count = snapshot.today.interruptions
        preventedPulls = snapshot.today.prevented
        actualPulls = snapshot.today.pulls
        activeSecondsToday = snapshot.today.activeSeconds
        week = snapshot.week
        hourOfWeek = snapshot.hourOfWeek
        weeklyTotal = snapshot.weeklyTotal
        weeklyRate = snapshot.weeklyRate
        weeklyImprovement = snapshot.weeklyImprovement
        lastDetection = snapshot.lastDetection
    }
}

// MARK: - Frame processing

extension Detector: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        autoreleasepool {   // keep the per-frame CoreVideo allocations from piling up
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            // Draw on every frame that arrives, so the preview stays as current as the camera allows
            // even when detection is throttled below it. Minimized nothing is drawn at all: the
            // floating window exists only to keep some of the app on screen so iOS permits the
            // camera, and it is transparent — see `PipWindowController`.
            if !display.isInPictureInPicture { display.enqueue(sampleBuffer) }
            // Throttle to the adaptive target rate — drop frames that arrive too soon.
            let now = CACurrentMediaTime()
            if now - lastProcessedTime < targetFrameInterval { return }
            lastProcessedTime = now
            process(pixelBuffer, at: now)   // already on captureQueue
        }
    }

    /// Runs on `captureQueue`. Vision in, `DetectionCore` out, publish what the UI needs.
    private func process(_ pixelBuffer: CVPixelBuffer, at now: CFTimeInterval) {
        guard !lock.withLock({ pausedFlag || backgrounded }) else { return }

        let dt = lastFrameTime == 0 ? 0 : now - lastFrameTime
        lastFrameTime = now
        stats.addActive(seconds: dt, at: Date())
        if dt > 0 {
            let inst = 1.0 / dt
            emaFps = emaFps == 0 ? inst : emaFps * 0.9 + inst * 0.1
        }
        rollDayIfNeeded()

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let aspect = height > 0 ? CGFloat(width) / CGFloat(height) : 3.0 / 4.0

        // --- Vision: periodic face check, hands only when a face (or its coasted zone) is there ---
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let runFace = frameIdx % max(1, faceEvery) == 0
        frameIdx &+= 1
        // The hand-pose request is the expensive one. With no face in view there's nothing to
        // catch, so we idle on just the cheap face check until someone's there.
        let runHands = lock.withLock { core.hasZone }
        var requests: [VNRequest] = []
        if runFace  { requests.append(faceRequest) }
        if runHands { requests.append(handRequest) }
        if !requests.isEmpty { try? handler.perform(requests) }

        let faces: [CGRect] = runFace
            ? (faceRequest.results ?? [])
                .sorted { $0.confidence > $1.confidence }
                .map(\.boundingBox)
            : []
        let handsNorm = runHands ? handPoints() : []

        let input = DetectionCore.FrameInput(time: now, ranFaceRequest: runFace,
                                             faces: faces, hands: handsNorm)
        let out = lock.withLock { core.process(input) }
        let wallClockNow = Date()
        if out.didStartTouch { stats.recordDetection(at: wallClockNow) }
        if out.didEndTouch { stats.recordOutcome(sustained: out.touchWasPull, at: wallClockNow) }
        lastLevel = out.level
        // The two non-visual cues for a lingering hand, each independent and off unless the user
        // switched it on. They keep going until the hand comes down. Blur is the third cue and is
        // handled in the view layer where the screen can actually be dimmed — which, minimized, is
        // nowhere: the floating window is transparent, so these two are all that reaches the user.
        if out.level >= 3 {
            if vibrateEnabled { Haptics.startSustained() } else { Haptics.stopSustained() }
            if voiceEnabled { CalmingTone.startSustained() } else { CalmingTone.stopSustained() }
        } else {
            Haptics.stopSustained()
            CalmingTone.stopSustained()
        }

        let fpsValue = emaFps
        let shouldPublishStats = out.didStartTouch || out.didEndTouch || now - lastStatsPublish >= 1
        let snapshot = shouldPublishStats ? stats.snapshot(at: wallClockNow) : nil
        if shouldPublishStats { lastStatsPublish = now }
        onMain {
            if let snapshot { self.applyStats(snapshot) }
            self.zone = out.zone
            self.hands = handsNorm
            self.touching = out.touching
            self.touchLevel = out.level
            self.hasFace = out.zone != nil
            self.fps = fpsValue
            self.bufferAspect = aspect
            if !self.connected { self.connected = true; self.errorText = nil }
        }
    }

    // MARK: Hands (Vision joints → MediaPipe 0..20 ordering, mirrored display coords)

    private func handPoints() -> [[CGPoint]] {
        guard let observations = handRequest.results else { return [] }
        var result: [[CGPoint]] = []
        for obs in observations {
            guard let points = try? obs.recognizedPoints(.all) else { continue }
            var hand: [CGPoint] = []
            hand.reserveCapacity(jointOrder.count)
            for joint in jointOrder {
                guard let p = points[joint], p.confidence > 0.3 else {
                    hand.append(CGPoint(x: -1, y: -1))   // off-screen sentinel for a missing joint
                    continue
                }
                // Vision location: normalized, bottom-left origin → display (top-left, mirrored).
                hand.append(CGPoint(x: 1 - p.location.x, y: 1 - p.location.y))
            }
            result.append(hand)
        }
        return result
    }
}

/// Vision hand joints in MediaPipe 0..20 order, so fingertip indices mean the same thing here
/// as they do on the Mac.
private let jointOrder: [VNHumanHandPoseObservation.JointName] = [
    .wrist,
    .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
    .indexMCP, .indexPIP, .indexDIP, .indexTip,
    .middleMCP, .middlePIP, .middleDIP, .middleTip,
    .ringMCP, .ringPIP, .ringDIP, .ringTip,
    .littleMCP, .littlePIP, .littleDIP, .littleTip,
]

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}
