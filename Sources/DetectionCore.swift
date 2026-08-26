import Foundation
import CoreGraphics

/// The whole "is a hand on the face?" decision, with no camera, no Vision and no UIKit.
///
/// This is a faithful port of the macOS `Detector`'s geometry and state machine (build the head
/// zone from the face box, stabilize it, test fingertips against it, debounce, escalate by how
/// long the hand lingers). Keeping it pure means two things: the simulator can test it without a
/// camera, and any drift away from the Mac's behaviour shows up as a failing test rather than as
/// a phone that catches touches slightly differently.
///
/// Coordinates: everything the core sees or returns is normalized 0…1 in *display* space —
/// top-left origin, mirrored like a selfie view. `Vision.boundingBox` values (bottom-left origin,
/// unmirrored) go through `displayRect` on the way in.
struct DetectionCore {

    /// Every tuning constant, in one place, with the Mac's values as defaults. `Config()` is what
    /// `ParityTests` checks against the macOS source, so please don't "improve" these here.
    struct Config: Equatable {
        /// Frames a hand must be in the zone before it counts as a touch.
        var minFrames = 3
        /// Frames a hand must be out of the zone before the touch is considered over.
        var releaseFrames = 5
        /// How much of the face box's width to add on each side before scaling.
        var marginSide = 0.5
        /// How much of the face box's height to add above (hair / forehead).
        var marginTop = 0.5
        /// How much to add below the chin.
        var marginBottom = 0.0
        /// Half-width / half-height multipliers applied to the margined box.
        var halfWidthScale = 0.80
        var halfHeightScale = 1.20
        /// A new zone this much smaller / larger than the stable one is treated as a glitch.
        var zoneAreaLo = 0.6
        var zoneAreaHi = 1.6
        /// A center jump beyond this fraction of the frame diagonal is treated as a glitch.
        var zoneCenterJump = 0.25
        /// How many suspicious zones in a row to reject before believing them.
        var zoneRejectMax = 3
        /// Smoothing factor for the accepted zone (1 = no smoothing).
        var zoneEMA = 0.5
        /// How long to keep using the last good zone while the face detector misses.
        var zoneCoastSecs: CFTimeInterval = 0.45
        /// Seconds in the zone before the touch escalates to level 2 / level 3. Level 3 is what
        /// the app reacts to (blur, or a buzz when minimized); level 2 is kept for parity with the
        /// Mac's escalation.
        var level2After: TimeInterval = 2.0
        var level3After: TimeInterval = 3.0
        /// Sensitivity: scales the head zone around its center.
        var zoneMultiplier = 1.0
    }

    /// One frame's worth of Vision output.
    struct FrameInput {
        /// Monotonic timestamp (`CACurrentMediaTime()` in the app, synthetic in tests).
        var time: CFTimeInterval
        /// Was the face request actually run on this frame? (The Mac runs it every 3rd frame.)
        var ranFaceRequest: Bool
        /// Face boxes as Vision reports them: normalized, bottom-left origin, unmirrored,
        /// ordered most-confident first (the Detector sorts them so the core stays pure).
        var faces: [CGRect] = []
        /// Hands as 21 display-space points each; a missing joint is the sentinel (-1, -1).
        var hands: [[CGPoint]] = []
    }

    /// What the app should do with this frame.
    struct FrameOutput: Equatable {
        /// The zone the hands were tested against — nil when no face is in view.
        var zone: [Double]?
        var touching = false
        /// 0 = away, 1 = touching, 2 = lingering (≥ level2After), 3 = sustained
        /// (≥ level3After — the blur / haptic threshold).
        var level = 0
        /// True on the single frame a touch begins — the counter increments here.
        var didStartTouch = false
        /// True on the single frame a touch ends.
        var didEndTouch = false
        /// On `didEndTouch`: did this touch reach level 3 before the hand pulled away?
        var touchWasPull = false
        /// On `didEndTouch`: how long the hand stayed in the zone.
        var touchDuration: TimeInterval = 0
        /// Which entry of `FrameInput.faces` the zone was built from, on frames that ran the face
        /// request and found one — nil otherwise. The core has no use for it; it is here so the
        /// caller can pull the *same* face out of its landmark pass and name the touched zone.
        /// Declared last so the existing memberwise calls keep working.
        var faceIndex: Int?
    }

    var config: Config

    // Mirrors of the Mac's per-frame detection state.
    private var stateTouching = false
    private var inStreak = 0
    private var outStreak = 0
    private var stableZone: [Double]?     // smoothed zone, used for outlier rejection
    private var zoneReject = 0
    private var coastZone: [Double]?      // last good zone, held through brief face misses
    private var activeZone: [Double]?     // what this frame's hands are tested against
    private var lastFaceTime: CFTimeInterval = 0
    private var touchStartTime: CFTimeInterval = 0
    private var touchReachedEffect = false

    init(config: Config = Config()) {
        self.config = config
    }

    /// True while a face (or its coasted zone) is in view — the app skips the expensive hand
    /// request otherwise, exactly like the Mac's `runHands = activeZone != nil`.
    var hasZone: Bool { activeZone != nil }

    /// Clear all live state — used when the camera stops (backgrounding, interruption).
    mutating func reset() {
        stateTouching = false
        inStreak = 0
        outStreak = 0
        stableZone = nil
        zoneReject = 0
        coastZone = nil
        activeZone = nil
        lastFaceTime = 0
        touchStartTime = 0
        touchReachedEffect = false
    }

    // MARK: - The per-frame loop

    mutating func process(_ input: FrameInput) -> FrameOutput {
        var pickedFace: Int?
        if input.ranFaceRequest { pickedFace = updateZone(faces: input.faces, now: input.time) }

        var inZone = false
        if let z = activeZone {
            for hand in input.hands where Self.tipInZone(hand, zone: z) { inZone = true; break }
        }

        // Debounce: entering needs minFrames, leaving needs releaseFrames.
        if inZone { inStreak += 1; outStreak = 0 } else { outStreak += 1; inStreak = 0 }

        var out = FrameOutput(zone: activeZone)
        out.faceIndex = pickedFace

        if !stateTouching, inStreak >= config.minFrames {
            stateTouching = true
            touchStartTime = input.time
            touchReachedEffect = false
            out.didStartTouch = true
        } else if stateTouching, outStreak >= config.releaseFrames {
            stateTouching = false
            out.didEndTouch = true
            out.touchWasPull = touchReachedEffect
            out.touchDuration = max(0, input.time - touchStartTime)
        }

        if stateTouching {
            let elapsed = input.time - touchStartTime
            out.level = elapsed >= config.level3After ? 3 : (elapsed >= config.level2After ? 2 : 1)
            if out.level >= 3 { touchReachedEffect = true }
        }
        out.touching = stateTouching
        return out
    }

    // MARK: - Zone (face → head zone, stabilized)

    /// - Returns: the index of the face the zone was built from, or nil when there was none.
    @discardableResult
    private mutating func updateZone(faces: [CGRect], now: CFTimeInterval) -> Int? {
        guard !faces.isEmpty else {
            // Face truly gone (turned away / left frame) past the coast window → drop the zone.
            if stableZone == nil || now - lastFaceTime > config.zoneCoastSecs {
                stableZone = nil; coastZone = nil; zoneReject = 0; activeZone = nil
            } else {
                activeZone = coastZone   // coast on the last zone through a brief miss
            }
            return nil
        }
        let index = pickDetection(faces)
        let raw = buildZone(faceRect: Self.displayRect(faces[index]))
        let (newStable, newReject, _) = stabilize(raw: raw, stable: stableZone, reject: zoneReject)
        stableZone = newStable
        zoneReject = newReject
        coastZone = newStable
        activeZone = newStable
        lastFaceTime = now
        return index
    }

    /// With a known previous zone, prefer the face nearest its center (tracking continuity);
    /// otherwise the most confident one — which is `faces[0]`, since the caller pre-sorts.
    ///
    /// Returns an index rather than the rect itself so the caller can pull the matching entry out
    /// of its landmark pass, which answers in the order it was asked.
    private func pickDetection(_ faces: [CGRect]) -> Int {
        if faces.count == 1 { return 0 }
        if let s = stableZone {
            let scx = (s[0] + s[2]) / 2, scy = (s[1] + s[3]) / 2
            return faces.indices.min { a, b in
                let ra = Self.displayRect(faces[a]), rb = Self.displayRect(faces[b])
                let da = pow(ra.midX - scx, 2) + pow(ra.midY - scy, 2)
                let db = pow(rb.midX - scx, 2) + pow(rb.midY - scy, 2)
                return da < db
            } ?? 0
        }
        return 0
    }

    /// Vision bbox (normalized, bottom-left origin) → display rect (top-left origin, mirrored).
    static func displayRect(_ b: CGRect) -> CGRect {
        CGRect(x: 1 - (b.origin.x + b.width), y: 1 - (b.origin.y + b.height),
               width: b.width, height: b.height)
    }

    /// Head-zone rectangle (normalized) from the face rect.
    func buildZone(faceRect f: CGRect) -> [Double] {
        var x0 = f.minX - config.marginSide * f.width
        var x1 = f.maxX + config.marginSide * f.width
        var y0 = f.minY - config.marginTop * f.height
        var y1 = f.maxY + config.marginBottom * f.height
        let cx = (x0 + x1) / 2, cy = (y0 + y1) / 2
        let m = config.zoneMultiplier
        let hw = (x1 - x0) / 2 * config.halfWidthScale * m
        let hh = (y1 - y0) / 2 * config.halfHeightScale * m
        x0 = cx - hw; x1 = cx + hw; y0 = cy - hh; y1 = cy + hh
        return [max(0, x0), max(0, y0), min(1, x1), min(1, y1)]
    }

    /// Smooth the zone and drop transient outliers.
    func stabilize(raw: [Double], stable: [Double]?, reject: Int)
        -> (stable: [Double], reject: Int, rejected: Bool) {
        guard let s = stable else { return (raw, 0, false) }
        func area(_ b: [Double]) -> Double { max(1e-6, b[2] - b[0]) * max(1e-6, b[3] - b[1]) }
        let ratio = area(raw) / area(s)
        let rcx = (raw[0] + raw[2]) / 2, rcy = (raw[1] + raw[3]) / 2
        let scx = (s[0] + s[2]) / 2, scy = (s[1] + s[3]) / 2
        let diag = (2.0).squareRoot()               // normalized frame diagonal
        let shift = (pow(rcx - scx, 2) + pow(rcy - scy, 2)).squareRoot() / diag
        let suspicious = ratio < config.zoneAreaLo || ratio > config.zoneAreaHi
            || shift > config.zoneCenterJump
        if suspicious, reject < config.zoneRejectMax { return (s, reject + 1, true) }
        let a = config.zoneEMA
        let blended = zip(raw, s).map { a * $0 + (1 - a) * $1 }
        return (blended, 0, false)
    }

    /// Does any fingertip fall inside the zone? Missing joints carry the (-1, -1) sentinel and
    /// can never be inside, so they need no special case.
    static func tipInZone(_ hand: [CGPoint], zone z: [Double]) -> Bool {
        guard z.count == 4 else { return false }
        for i in fingertipIndices where i < hand.count {
            let p = hand[i]
            if p.x >= z[0], p.x <= z[2], p.y >= z[1], p.y <= z[3] { return true }
        }
        return false
    }
}

/// Fingertip indices in the MediaPipe 21-landmark layout (thumb…pinky tips).
let fingertipIndices: Set<Int> = [4, 8, 12, 16, 20]

/// How sensitive the head zone is — scales it around its center.
enum TouchSensitivity: String, CaseIterable {
    case less     = "less"
    case standard = "standard"
    case high     = "high"

    var zoneMultiplier: Double {
        switch self {
        case .less:     return 0.75
        case .standard: return 1.0
        case .high:     return 1.35
        }
    }
}
