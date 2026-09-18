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
    /// 0 = away, 1 = touching, 2 = lingering, 3 = sustained.
    @Published var touchLevel = 0
    @Published var count = 0                  // today's detections
    @Published private(set) var preventedPulls = 0
    @Published private(set) var actualPulls = 0
    @Published private(set) var activeSecondsToday = 0.0
    @Published private(set) var week: [MobileStatsStore.DayBar] = []
    @Published private(set) var history: [MobileStatsStore.DayBar] = []
    /// Today hour by hour, and the same for every day in `week` keyed by its id — what the Today
    /// heatmap draws for whichever day the week strip has selected.
    @Published private(set) var chartDay: [MobileStatsStore.DayBar] = []
    @Published private(set) var hoursByDay: [String: [MobileStatsStore.DayBar]] = [:]
    @Published private(set) var hourOfWeek = Array(repeating: 0, count: 24)
    @Published private(set) var weeklyTotal = 0
    @Published private(set) var weeklyRate = 0.0
    @Published private(set) var weeklyImprovement: Double?
    /// Earned mobile badges persist after their qualifying period passes, just like their desktop
    /// counterparts. Only opaque badge IDs are stored.
    @Published private(set) var unlockedAchievementIDs: Set<String> = []
    /// Today's completed touches per head zone, keyed by `ZoneHit.name` — what the Today page's
    /// head draws a number over.
    @Published private(set) var zoneCounts: [String: Int] = [:]
    @Published private(set) var zonesByDay: [String: [String: Int]] = [:]
    @Published private(set) var lastDetection: Date?
    @Published var fps = 0.0
    @Published var hasFace = false
    @Published var connected = false          // camera running and delivering frames
    /// The same flag as `isPaused`, published for the UI: the header's camera switch reads it, and
    /// it is the user's own intent, not the session's state — a phone call can stop capture without
    /// ever touching this.
    @Published private(set) var paused = false
    @Published var errorText: String?
    /// Width / height of the camera buffer, so the overlay can undo the preview's aspect fill.
    @Published var bufferAspect: CGFloat = 3.0 / 4.0

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

    /// Calibration mode — used by the onboarding detection check, where the person is asked to move
    /// their hand to their face on purpose. Detection and everything it publishes (`zone`,
    /// `touching`, `hasFace`, …) carry on as normal; only the *recording* and the cues stop, so a
    /// rehearsal never lands in the day's history and the phone does not buzz at a movement the
    /// screen just asked for.
    var calibrating: Bool {
        get { lock.withLock { calibratingFlag } }
        set { lock.withLock { calibratingFlag = newValue } }
    }

    /// The core is read on the capture queue and its config is written from the main thread, so
    /// unlike the rest of the detection state it does need the lock.
    private var core = DetectionCore()
    private let lock = NSLock()
    private var vibrateEnabledFlag = true
    private var voiceEnabledFlag = false
    private var calibratingFlag = false
    private var pausedFlag = false
    private var backgrounded = false
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
    private let achievementDefaultsKey = "awaira.mobile.unlockedAchievements.v1"
    /// Names *where* on the head each finished touch landed. Like `stats`, it lives on the capture
    /// queue and is touched from nowhere else, so it needs no lock — unlike `core`, whose config the
    /// UI writes.
    private let zoneTracker = TouchZoneTracker()
    /// The face-space frame of the last face pass, rebuilt whenever the landmark stage answers.
    private var faceFrame: FaceFrame?

    /// Run the face request every Nth frame, as on the Mac.
    private let faceEvery = 3

    private let log = Logger(subsystem: "com.awaira.ios", category: "capture")

    // MARK: Vision requests (reused across frames)
    private let faceRequest = VNDetectFaceRectanglesRequest()
    /// The landmark stage, chained onto the boxes above via `inputFaceObservations` rather than run
    /// standalone — it only has to refine faces the cheap pass already found. Feeds `FaceFrame`,
    /// which is what turns "a hand is on the head" into "on the right cheek".
    private let landmarkRequest = VNDetectFaceLandmarksRequest()
    private let handRequest: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()

    /// The detector is created from the UI and observes the app lifecycle there.
    @MainActor override init() {
        super.init()
        unlockedAchievementIDs = Set(UserDefaults.standard.stringArray(forKey: achievementDefaultsKey) ?? [])
        if ProcessInfo.processInfo.arguments.contains("-ScreenshotDemo") {
            stats.loadScreenshotDemo()
        }
        applyStats(stats.snapshot())
        updateQualityForThermalState()
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

    /// Clears the local aggregate history and badge state without touching the live camera
    /// session. Frames are never stored, but this gives people a direct way to erase the local
    /// records created from detections.
    func deleteLocalData() {
        captureQueue.async { [weak self] in
            guard let self else { return }
            self.stats.deleteAll()
            self.core.reset()
            self.lastLevel = 0
            self.todayKey = Self.isoDay(Date())
            let snapshot = self.stats.snapshot()
            self.onMain {
                self.unlockedAchievementIDs = []
                UserDefaults.standard.removeObject(forKey: self.achievementDefaultsKey)
                self.applyStats(snapshot)
            }
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

    /// Stop and restart detection without tearing the capture session down — the session's inputs
    /// are wired once, in `configureAndRun`, so this is the only way to switch the camera off and
    /// back on. `stop()` is final by comparison: nothing rebuilds the session afterwards.
    func togglePause() {
        let nowPaused = lock.withLock { pausedFlag.toggle(); return pausedFlag }
        captureQueue.async { [weak self] in
            guard let self else { return }
            if nowPaused { self.session.stopRunning(); self.core.reset() }
            else if !self.lock.withLock({ self.backgrounded }) { self.session.startRunning() }
        }
        onMain { self.paused = nowPaused }
        if nowPaused { clearLiveState() }
    }

    /// Read from the capture queue, where the frame loop gates on it.
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

    /// Calls, system camera contention, and similar interruptions reset the live detection state.
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

    /// Bring capture back after a foreground return or interruption.
    private func resumeCapture() {
        guard started, !lock.withLock({ pausedFlag || backgrounded }) else { return }
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
        history = snapshot.history
        chartDay = snapshot.todayHours
        hoursByDay = snapshot.hoursByDay
        hourOfWeek = snapshot.hourOfWeek
        weeklyTotal = snapshot.weeklyTotal
        weeklyRate = snapshot.weeklyRate
        weeklyImprovement = snapshot.weeklyImprovement
        let newlyEligible = MobileAchievementEvaluator.eligible(in: snapshot.history,
                                                                 weeklyImprovement: snapshot.weeklyImprovement)
        let mergedAchievements = unlockedAchievementIDs.union(newlyEligible)
        if mergedAchievements != unlockedAchievementIDs {
            unlockedAchievementIDs = mergedAchievements
            UserDefaults.standard.set(Array(mergedAchievements).sorted(), forKey: achievementDefaultsKey)
        }
        zoneCounts = snapshot.todayZones
        zonesByDay = snapshot.zonesByDay
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

        // The observations themselves, not just their boxes: the landmark stage runs on them, and
        // the core reports back which one it picked so the same face can be looked up here.
        let observations: [VNFaceObservation] = runFace
            ? (faceRequest.results ?? []).sorted { $0.confidence > $1.confidence }
            : []

        // Second pass, only when there is a face to work with: the landmark stage runs on the boxes
        // the request above just produced. A failure here costs nothing — the zone label goes
        // missing for that touch, and everything the app counts carries on from the box alone. The
        // results are read only when the pass actually succeeded, because `landmarkRequest` keeps
        // the previous pass's answers and a face from 0.6 s ago would be classified as if it were
        // this one's.
        var landmarked: [VNFaceObservation] = []
        if runFace, !observations.isEmpty {
            landmarkRequest.inputFaceObservations = observations
            do {
                try handler.perform([landmarkRequest])
                landmarked = landmarkRequest.results ?? []
            } catch {
                log.debug("face landmarks failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        let handsNorm = runHands ? handPoints() : []

        let input = DetectionCore.FrameInput(time: now, ranFaceRequest: runFace,
                                             faces: observations.map(\.boundingBox), hands: handsNorm)
        let out = lock.withLock { core.process(input) }

        // The landmark pass answers in the order it was asked, so the core's index names the same
        // face here. If it came back short, or without landmarks for this one, the zone label is
        // simply skipped — the head zone does not depend on it. On the frames between face passes
        // there is nothing to rebuild from, and the tracker holds the last frame itself.
        let frameSize = CGSize(width: width, height: height)
        if let index = out.faceIndex, index < landmarked.count {
            faceFrame = buildFaceFrame(landmarked[index], frameSize: frameSize)
        } else {
            faceFrame = nil
        }
        let wallClockNow = Date()
        // Read once per frame: the onboarding check rehearses touches on request, and nothing it
        // sees is recorded or reacted to.
        let calibrating = lock.withLock { calibratingFlag }
        if out.didStartTouch, !calibrating { stats.recordDetection(at: wallClockNow) }
        if out.didEndTouch, !calibrating {
            stats.recordOutcome(sustained: out.touchWasPull,
                                at: wallClockNow,
                                duration: out.touchDuration)
        }

        // Zone labelling. Runs *after* the core has spoken and only reads its result — a touch is
        // counted, extended and ended exactly as it was before this existed. A touch the classifier
        // never named (hand in the head box but off the head, or the face lost for its whole
        // duration) records nothing, so the zone totals are legitimately smaller than the day's
        // interruption count. Before the snapshot below, so the frame that ends a touch already
        // publishes its zone.
        if let finished = zoneTracker.update(faceFrame: faceFrame, faceChecked: runFace,
                                             hands: handsNorm, zone: out.zone,
                                             touching: out.touching, frameSize: frameSize),
           !calibrating {
            stats.recordZone(finished.name, at: wallClockNow)
        }
        lastLevel = out.level
        // The two non-visual cues for a lingering hand, each independent and off unless the user
        // switched it on. They keep going until the hand comes down. Blur is the third cue and is
        // handled in the view layer where the screen can actually be dimmed.
        if out.level >= 3, !calibrating {
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

    // MARK: Face landmarks → the classifier's coordinate system

    /// Face-space coordinate system for the touch-zone classifier, in the same mirrored display
    /// pixels the hand landmarks arrive in.
    ///
    /// Ported from the Mac's `Detector.buildFaceFrame`. Vision hands back outlines, not the five
    /// points YuNet gives the Windows app, so the mouth corners have to be picked out of the lip
    /// outline: they are its two extremes along the eye line. That axis is known before `FaceFrame`
    /// exists, so it is computed here first.
    ///
    /// Which eye Vision calls left and which right does not matter — swapping them only flips the
    /// sign of `u`, and the classifier uses `|u|` for the zone and the display x for the side.
    private func buildFaceFrame(_ observation: VNFaceObservation, frameSize size: CGSize) -> FaceFrame? {
        guard let landmarks = observation.landmarks,
              let leftEyeRegion = landmarks.leftEye,
              let rightEyeRegion = landmarks.rightEye,
              let lipsRegion = landmarks.outerLips else { return nil }

        // `pointsInImage` is in image pixels with a bottom-left origin; the rest of the detector
        // works in mirrored, top-left display pixels.
        func toDisplay(_ region: VNFaceLandmarkRegion2D) -> [CGPoint] {
            region.pointsInImage(imageSize: size).map {
                CGPoint(x: size.width - $0.x, y: size.height - $0.y)
            }
        }
        func centroid(_ points: [CGPoint]) -> CGPoint? {
            guard !points.isEmpty else { return nil }
            let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
        }

        guard let leftEye = centroid(toDisplay(leftEyeRegion)),
              let rightEye = centroid(toDisplay(rightEyeRegion)) else { return nil }

        // The nose only decides which way +v points, so the middle of whichever nose outline Vision
        // returned is precise enough.
        let noseRegion = landmarks.nose ?? landmarks.noseCrest
        guard let noseTip = noseRegion.flatMap({ centroid(toDisplay($0)) }) else { return nil }

        let lips = toDisplay(lipsRegion)
        guard lips.count >= 2 else { return nil }
        let origin = CGPoint(x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2)
        let dx = leftEye.x - rightEye.x, dy = leftEye.y - rightEye.y
        let ipd = (dx * dx + dy * dy).squareRoot()
        guard ipd >= 4 else { return nil }
        let ex = CGVector(dx: dx / ipd, dy: dy / ipd)
        func alongEyeLine(_ p: CGPoint) -> CGFloat {
            (p.x - origin.x) * ex.dx + (p.y - origin.y) * ex.dy
        }
        guard let cornerA = lips.min(by: { alongEyeLine($0) < alongEyeLine($1) }),
              let cornerB = lips.max(by: { alongEyeLine($0) < alongEyeLine($1) }) else { return nil }

        return FaceFrame(leftEye: leftEye, rightEye: rightEye, noseTip: noseTip,
                         mouthLeft: cornerA, mouthRight: cornerB)
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
