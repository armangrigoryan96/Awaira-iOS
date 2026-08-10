import XCTest
@testable import Awaira

/// Drives `DetectionCore` with synthetic frames — no camera, so this runs on the simulator.
final class DetectionCoreTests: XCTestCase {

    // MARK: Helpers

    /// A Vision-style face box (bottom-left origin) centered in the frame.
    private func face(cx: Double = 0.5, cy: Double = 0.5, w: Double = 0.2, h: Double = 0.25) -> CGRect {
        CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// A 21-point hand where every joint sits at `p`, so all fingertips are at `p` too.
    private func hand(at p: CGPoint) -> [CGPoint] { Array(repeating: p, count: 21) }

    /// A hand with only one joint on screen; every other joint is the "not found" sentinel.
    private func hand(joint: Int, at p: CGPoint) -> [CGPoint] {
        var h = Array(repeating: CGPoint(x: -1, y: -1), count: 21)
        h[joint] = p
        return h
    }

    private func center(of zone: [Double]) -> CGPoint {
        CGPoint(x: (zone[0] + zone[2]) / 2, y: (zone[1] + zone[3]) / 2)
    }

    /// Feed `n` frames, 0.2 s apart (the app's ~5 fps), returning the last output.
    @discardableResult
    private func run(_ core: inout DetectionCore, frames n: Int, from t0: CFTimeInterval = 100,
                     step: CFTimeInterval = 0.2, faces: [CGRect], hands: [[CGPoint]])
        -> DetectionCore.FrameOutput {
        var out = DetectionCore.FrameOutput()
        for i in 0..<n {
            out = core.process(.init(time: t0 + Double(i) * step, ranFaceRequest: true,
                                     faces: faces, hands: hands))
        }
        return out
    }

    // MARK: Zone geometry

    func testBuildZoneGoldenValues() {
        let core = DetectionCore()
        // Face box in display space: x 0.4…0.6, y 0.375…0.625 (w 0.2, h 0.25).
        let f = CGRect(x: 0.4, y: 0.375, width: 0.2, height: 0.25)
        // Margined: x 0.3…0.7 (w 0.4), y 0.25…0.625 (h 0.375). Center (0.5, 0.4375).
        // hw = 0.2 * 0.80 = 0.16, hh = 0.1875 * 1.20 = 0.225.
        let z = core.buildZone(faceRect: f)
        XCTAssertEqual(z[0], 0.34,   accuracy: 1e-9)
        XCTAssertEqual(z[1], 0.2125, accuracy: 1e-9)
        XCTAssertEqual(z[2], 0.66,   accuracy: 1e-9)
        XCTAssertEqual(z[3], 0.6625, accuracy: 1e-9)
    }

    func testBuildZoneExtendsUpwardForHair() {
        let core = DetectionCore()
        let f = CGRect(x: 0.4, y: 0.375, width: 0.2, height: 0.25)
        let z = core.buildZone(faceRect: f)
        let headroom = f.minY - z[1]      // top-left origin: above the face
        let chinroom = z[3] - f.maxY      // below the chin
        XCTAssertEqual(headroom, 0.1625, accuracy: 1e-9)
        XCTAssertEqual(chinroom, 0.0375, accuracy: 1e-9)
        XCTAssertGreaterThan(headroom, chinroom, "the zone extends upward for hair")
    }

    func testBuildZoneClampsToFrame() {
        let core = DetectionCore()
        let z = core.buildZone(faceRect: CGRect(x: -0.05, y: 0.0, width: 0.3, height: 0.4))
        XCTAssertGreaterThanOrEqual(z[0], 0)
        XCTAssertGreaterThanOrEqual(z[1], 0)
        XCTAssertLessThanOrEqual(z[2], 1)
        XCTAssertLessThanOrEqual(z[3], 1)
    }

    func testZoneMultiplierScalesAroundCenter() {
        let f = CGRect(x: 0.4, y: 0.375, width: 0.2, height: 0.25)
        let standard = DetectionCore().buildZone(faceRect: f)
        for sensitivity in TouchSensitivity.allCases {
            var config = DetectionCore.Config()
            config.zoneMultiplier = sensitivity.zoneMultiplier
            let z = DetectionCore(config: config).buildZone(faceRect: f)
            XCTAssertEqual(center(of: z).x, center(of: standard).x, accuracy: 1e-9)
            XCTAssertEqual(center(of: z).y, center(of: standard).y, accuracy: 1e-9)
            let width = z[2] - z[0], stdWidth = standard[2] - standard[0]
            XCTAssertEqual(width, stdWidth * sensitivity.zoneMultiplier, accuracy: 1e-9)
        }
    }

    func testDisplayRectMirrorsAndFlipsOrigin() {
        // Vision box hugging the bottom-left corner → display box at the top-right.
        let d = DetectionCore.displayRect(CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.3))
        XCTAssertEqual(d.minX, 0.8, accuracy: 1e-9)
        XCTAssertEqual(d.minY, 0.7, accuracy: 1e-9)
        XCTAssertEqual(d.width, 0.2, accuracy: 1e-9)
        XCTAssertEqual(d.height, 0.3, accuracy: 1e-9)
    }

    // MARK: Stabilization

    func testStabilizeAcceptsFirstZoneAsIs() {
        let core = DetectionCore()
        let raw = [0.1, 0.2, 0.3, 0.4]
        let (stable, reject, rejected) = core.stabilize(raw: raw, stable: nil, reject: 0)
        XCTAssertEqual(stable, raw)
        XCTAssertEqual(reject, 0)
        XCTAssertFalse(rejected)
    }

    func testStabilizeBlendsWithEMA() {
        let core = DetectionCore()
        let stable = [0.2, 0.2, 0.4, 0.4]
        let raw    = [0.22, 0.22, 0.42, 0.42]      // same size, tiny shift → accepted
        let (blended, reject, rejected) = core.stabilize(raw: raw, stable: stable, reject: 0)
        XCTAssertFalse(rejected)
        XCTAssertEqual(reject, 0)
        for (b, expected) in zip(blended, [0.21, 0.21, 0.41, 0.41]) {
            XCTAssertEqual(b, expected, accuracy: 1e-9)   // EMA 0.5 = midpoint
        }
    }

    func testStabilizeRejectsAreaOutlierUpToThreeTimesThenAccepts() {
        let core = DetectionCore()
        let stable = [0.2, 0.2, 0.4, 0.4]          // area 0.04
        let raw    = [0.25, 0.25, 0.35, 0.35]      // area 0.01 → ratio 0.25 < 0.6
        var current = stable
        var reject = 0
        for expected in 1...3 {
            let r = core.stabilize(raw: raw, stable: current, reject: reject)
            XCTAssertTrue(r.rejected, "outlier \(expected) should be rejected")
            XCTAssertEqual(r.stable, stable, "a rejected zone must not move the stable one")
            current = r.stable
            reject = r.reject
            XCTAssertEqual(reject, expected)
        }
        // The fourth suspicious frame in a row is believed — the face really did move.
        let r = core.stabilize(raw: raw, stable: current, reject: reject)
        XCTAssertFalse(r.rejected)
        XCTAssertEqual(r.reject, 0)
        XCTAssertNotEqual(r.stable, stable)
    }

    func testStabilizeRejectsCenterJump() {
        let core = DetectionCore()
        let stable = [0.1, 0.1, 0.3, 0.3]
        let raw    = [0.7, 0.7, 0.9, 0.9]          // same area, center jumps ~0.42 of the diagonal
        let r = core.stabilize(raw: raw, stable: stable, reject: 0)
        XCTAssertTrue(r.rejected)
        XCTAssertEqual(r.stable, stable)
    }

    // MARK: Coasting

    func testZoneCoastsThroughBriefFaceMissThenDrops() {
        var core = DetectionCore()
        let f = face()
        _ = core.process(.init(time: 100, ranFaceRequest: true, faces: [f]))
        XCTAssertNotNil(core.process(.init(time: 100.2, ranFaceRequest: true, faces: [f])).zone)

        // Face missing for 0.4 s (< zoneCoastSecs 0.45) → the zone is held.
        let coasted = core.process(.init(time: 100.6, ranFaceRequest: true, faces: []))
        XCTAssertNotNil(coasted.zone, "a brief face miss should coast on the last good zone")

        // Still missing past the coast window → dropped.
        let dropped = core.process(.init(time: 101.0, ranFaceRequest: true, faces: []))
        XCTAssertNil(dropped.zone)
        XCTAssertFalse(core.hasZone)
    }

    func testFramesWithoutFaceRequestKeepTheZone() {
        var core = DetectionCore()
        _ = core.process(.init(time: 100, ranFaceRequest: true, faces: [face()]))
        // The app only runs the face request every 3rd frame; the others must not clear anything.
        let out = core.process(.init(time: 100.2, ranFaceRequest: false, faces: []))
        XCTAssertNotNil(out.zone)
    }

    // MARK: Fingertips

    func testOnlyFingertipsCount() {
        let zone = [0.4, 0.4, 0.6, 0.6]
        let inside = CGPoint(x: 0.5, y: 0.5)
        for tip in [4, 8, 12, 16, 20] {
            XCTAssertTrue(DetectionCore.tipInZone(hand(joint: tip, at: inside), zone: zone),
                          "fingertip \(tip) inside the zone must count")
        }
        for other in [0, 1, 5, 9, 13, 17, 19] {
            XCTAssertFalse(DetectionCore.tipInZone(hand(joint: other, at: inside), zone: zone),
                           "non-fingertip joint \(other) must not count")
        }
    }

    func testMissingJointSentinelIsNeverInside() {
        let zone = [0.0, 0.0, 1.0, 1.0]           // whole frame
        let allMissing = Array(repeating: CGPoint(x: -1, y: -1), count: 21)
        XCTAssertFalse(DetectionCore.tipInZone(allMissing, zone: zone))
    }

    func testZoneBoundaryCountsAsInside() {
        let zone = [0.4, 0.4, 0.6, 0.6]
        XCTAssertTrue(DetectionCore.tipInZone(hand(joint: 8, at: CGPoint(x: 0.4, y: 0.4)), zone: zone))
        XCTAssertTrue(DetectionCore.tipInZone(hand(joint: 8, at: CGPoint(x: 0.6, y: 0.6)), zone: zone))
        XCTAssertFalse(DetectionCore.tipInZone(hand(joint: 8, at: CGPoint(x: 0.6001, y: 0.5)), zone: zone))
    }

    func testNoTouchWithoutAFace() {
        var core = DetectionCore()
        let out = run(&core, frames: 10, faces: [], hands: [hand(at: CGPoint(x: 0.5, y: 0.5))])
        XCTAssertFalse(out.touching)
        XCTAssertNil(out.zone)
    }

    // MARK: Debounce

    func testTouchNeedsThreeFramesInZone() {
        var core = DetectionCore()
        let f = face()
        let inZone = [hand(at: CGPoint(x: 0.5, y: 0.5))]   // face is centered, so this is in the zone
        var starts = 0

        for i in 0..<2 {
            let out = core.process(.init(time: 100 + Double(i) * 0.2, ranFaceRequest: true,
                                         faces: [f], hands: inZone))
            if out.didStartTouch { starts += 1 }
            XCTAssertFalse(out.touching, "two frames in the zone must not be a touch yet")
        }
        let third = core.process(.init(time: 100.4, ranFaceRequest: true, faces: [f], hands: inZone))
        XCTAssertTrue(third.didStartTouch)
        XCTAssertTrue(third.touching)
        XCTAssertEqual(third.level, 1)
        XCTAssertEqual(starts, 0)
    }

    func testReleaseNeedsFiveFramesOutOfZone() {
        var core = DetectionCore()
        let f = face()
        let inZone = [hand(at: CGPoint(x: 0.5, y: 0.5))]
        let away   = [hand(at: CGPoint(x: 0.05, y: 0.95))]
        run(&core, frames: 3, faces: [f], hands: inZone)

        for i in 0..<4 {
            let out = core.process(.init(time: 101 + Double(i) * 0.2, ranFaceRequest: true,
                                         faces: [f], hands: away))
            XCTAssertTrue(out.touching, "four frames away is not yet a release (frame \(i))")
            XCTAssertFalse(out.didEndTouch)
        }
        let fifth = core.process(.init(time: 101.8, ranFaceRequest: true, faces: [f], hands: away))
        XCTAssertTrue(fifth.didEndTouch)
        XCTAssertFalse(fifth.touching)
        XCTAssertEqual(fifth.level, 0)
    }

    func testFlickeringDoesNotDoubleCount() {
        var core = DetectionCore()
        let f = face()
        let inZone = [hand(at: CGPoint(x: 0.5, y: 0.5))]
        let away   = [hand(at: CGPoint(x: 0.05, y: 0.95))]
        var starts = 0
        var t: CFTimeInterval = 100

        // In for 3 (a touch), then alternate in/out — never 5 out in a row, so the touch holds.
        for _ in 0..<3 {
            if core.process(.init(time: t, ranFaceRequest: true, faces: [f], hands: inZone)).didStartTouch {
                starts += 1
            }
            t += 0.2
        }
        for i in 0..<12 {
            let hands = i % 2 == 0 ? away : inZone
            let out = core.process(.init(time: t, ranFaceRequest: true, faces: [f], hands: hands))
            if out.didStartTouch { starts += 1 }
            t += 0.2
        }
        XCTAssertEqual(starts, 1, "a flickering hand must count as one touch")
    }

    // MARK: Levels

    func testLevelsEscalateWithTime() {
        var core = DetectionCore()
        let f = face()
        let inZone = [hand(at: CGPoint(x: 0.5, y: 0.5))]
        var out = run(&core, frames: 3, from: 100, faces: [f], hands: inZone)
        XCTAssertEqual(out.level, 1)                    // touch starts at t = 100.4

        out = core.process(.init(time: 102.2, ranFaceRequest: true, faces: [f], hands: inZone))
        XCTAssertEqual(out.level, 1, "1.8 s in is still level 1")

        out = core.process(.init(time: 102.5, ranFaceRequest: true, faces: [f], hands: inZone))
        XCTAssertEqual(out.level, 2, "past 2.0 s the touch is lingering")

        out = core.process(.init(time: 103.3, ranFaceRequest: true, faces: [f], hands: inZone))
        XCTAssertEqual(out.level, 2, "2.9 s in is still level 2")

        out = core.process(.init(time: 103.5, ranFaceRequest: true, faces: [f], hands: inZone))
        XCTAssertEqual(out.level, 3, "at 3.0 s it buzzes")
    }

    func testShortTouchIsNotAPull() {
        var core = DetectionCore()
        let f = face()
        let inZone = [hand(at: CGPoint(x: 0.5, y: 0.5))]
        let away   = [hand(at: CGPoint(x: 0.05, y: 0.95))]
        run(&core, frames: 3, from: 100, faces: [f], hands: inZone)   // touch begins at 100.4
        var out = DetectionCore.FrameOutput()
        for i in 0..<5 {                                             // released by 101.4, < 3 s
            out = core.process(.init(time: 100.6 + Double(i) * 0.2, ranFaceRequest: true,
                                     faces: [f], hands: away))
        }
        XCTAssertTrue(out.didEndTouch)
        XCTAssertFalse(out.touchWasPull)
        XCTAssertEqual(out.touchDuration, 1.0, accuracy: 1e-6)
    }

    func testTouchThatReachedLevelThreeIsAPull() {
        var core = DetectionCore()
        let f = face()
        let inZone = [hand(at: CGPoint(x: 0.5, y: 0.5))]
        let away   = [hand(at: CGPoint(x: 0.05, y: 0.95))]
        run(&core, frames: 3, from: 100, faces: [f], hands: inZone)   // begins at 100.4
        _ = core.process(.init(time: 104, ranFaceRequest: true, faces: [f], hands: inZone))  // level 3
        var out = DetectionCore.FrameOutput()
        for i in 0..<5 {
            out = core.process(.init(time: 104.2 + Double(i) * 0.2, ranFaceRequest: true,
                                     faces: [f], hands: away))
        }
        XCTAssertTrue(out.didEndTouch)
        XCTAssertTrue(out.touchWasPull, "the effect had already fired before the hand moved")
    }

    func testResetClearsEverything() {
        var core = DetectionCore()
        let f = face()
        run(&core, frames: 5, faces: [f], hands: [hand(at: CGPoint(x: 0.5, y: 0.5))])
        XCTAssertTrue(core.hasZone)
        core.reset()
        XCTAssertFalse(core.hasZone)
        let out = core.process(.init(time: 200, ranFaceRequest: true, faces: [],
                                     hands: [hand(at: CGPoint(x: 0.5, y: 0.5))]))
        XCTAssertFalse(out.touching)
        XCTAssertNil(out.zone)
    }
}
