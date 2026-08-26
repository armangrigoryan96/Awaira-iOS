import XCTest
@testable import Awaira

/// The iPhone app must detect exactly like the Mac one — not better, not worse.
///
/// Every constant below is copied from `awaira/frontend/Sources/Detector.swift` (line numbers are
/// from the version this port was made against). If someone "tunes" the phone, this test fails and
/// the divergence is a deliberate, visible decision rather than a silent drift.
final class ParityTests: XCTestCase {

    func testConfigMatchesMacDetector() {
        let c = DetectionCore.Config()
        XCTAssertEqual(c.minFrames, 3)                  // Detector.swift: minFrames
        XCTAssertEqual(c.releaseFrames, 5)              // releaseFrames
        XCTAssertEqual(c.marginSide, 0.5)               // marginSide
        XCTAssertEqual(c.marginTop, 0.5)                // marginTop
        XCTAssertEqual(c.marginBottom, 0.0)             // marginBottom
        XCTAssertEqual(c.halfWidthScale, 0.80)          // buildZone: hw … * 0.80
        XCTAssertEqual(c.halfHeightScale, 1.20)         // buildZone: hh … * 1.20
        XCTAssertEqual(c.zoneAreaLo, 0.6)               // zoneAreaLo
        XCTAssertEqual(c.zoneAreaHi, 1.6)               // zoneAreaHi
        XCTAssertEqual(c.zoneCenterJump, 0.25)          // zoneCenterJump
        XCTAssertEqual(c.zoneRejectMax, 3)              // zoneRejectMax
        XCTAssertEqual(c.zoneEMA, 0.5)                  // zoneEMA
        XCTAssertEqual(c.zoneCoastSecs, 0.45)           // zoneCoastSecs
        XCTAssertEqual(c.level2After, 2.0)              // _level2After
        XCTAssertEqual(c.zoneMultiplier, 1.0)           // _zoneMultiplier
    }

    /// The phone dims as soon as a touch registers (level 1) and buzzes once the hand has been
    /// there for three seconds. The Mac instead waits 2 s for its effect.
    func testHapticThresholdIsThreeSeconds() {
        XCTAssertEqual(DetectionCore.Config().level3After, 3.0)
    }

    func testFingertipIndicesMatchMediaPipeLayout() {
        XCTAssertEqual(fingertipIndices, [4, 8, 12, 16, 20])
    }

    func testSensitivityMultipliers() {
        XCTAssertEqual(TouchSensitivity.less.zoneMultiplier, 0.75)
        XCTAssertEqual(TouchSensitivity.standard.zoneMultiplier, 1.0)
        XCTAssertEqual(TouchSensitivity.high.zoneMultiplier, 1.35)
    }

    // MARK: - Zone classifier

    /// `FaceFrame.swift` is a verbatim copy of the Mac's, and its thresholds are a calibrated set —
    /// measured at a camera, not rounded off. These probe each one from both sides, so a "tidy-up"
    /// of any constant fails here instead of quietly moving where a touch is filed.
    ///
    /// Both platforms run Apple's Vision, so nothing below is allowed to differ. The one number
    /// that *does* differ from Windows is the crown, and it is called out in its own test.
    private func zone(u: CGFloat, vn: CGFloat) -> String {
        FaceFixture.upright().classify(FaceFixture.point(u: u, vn: vn), fingertipIndex: 8).name
    }

    func testVerticalBandsOfTheCentralColumn() {
        XCTAssertEqual(zone(u: 0, vn: -0.36), "forehead")   // FaceFrame: case ..<(-0.35)
        XCTAssertEqual(zone(u: 0, vn: -0.34), "eye-left")   // exactly on the axis, dx 0 → "left"
        XCTAssertEqual(zone(u: 0, vn:  0.34), "eye-left")   // case ..<0.35
        XCTAssertEqual(zone(u: 0, vn:  0.36), "nose")
        XCTAssertEqual(zone(u: 0, vn:  0.79), "nose")       // case ..<0.80
        XCTAssertEqual(zone(u: 0, vn:  0.81), "mouth")
        XCTAssertEqual(zone(u: 0, vn:  1.24), "mouth")      // case ..<1.25
        XCTAssertEqual(zone(u: 0, vn:  1.26), "chin")
        XCTAssertEqual(zone(u: 0, vn:  1.99), "chin")       // case ..<2.00
        XCTAssertEqual(zone(u: 0, vn:  2.01), "neck")
    }

    /// The crown sits at -1.58 here where Windows uses -1.70: Vision's landmarks put a face on a
    /// vertical scale about 7% shorter than YuNet's five points, and the ported constant landed
    /// above the top of the head, making the zone unreachable. Do not "restore" the Windows value.
    func testCrownThresholdIsTheVisionCalibratedOne() {
        XCTAssertEqual(zone(u: 0, vn: -1.59), "topofhead")
        XCTAssertEqual(zone(u: 0, vn: -1.57), "hair-left")
        XCTAssertEqual(zone(u: 0, vn: -1.70), "topofhead",
                       "Windows' own threshold must still be inside the crown, not above it")
        XCTAssertEqual(zone(u: 0, vn: -1.14), "forehead")   // hair starts at -1.15
        XCTAssertEqual(zone(u: 0, vn: -1.16), "hair-left")
    }

    /// The ear's front edge is at 0.85 on the head artwork and its outer rim at 1.24, so the gate
    /// is 0.90 — at the 1.15 this started as, the front two thirds of the ear were filed as cheek.
    func testEarGateAndItsVerticalWindow() {
        XCTAssertEqual(zone(u: 0.91, vn: 0.30), "ear-left")
        XCTAssertEqual(zone(u: 0.89, vn: 0.30), "cheek-left", "just inside the gate is still cheek")
        XCTAssertEqual(zone(u: 1.00, vn: -0.10), "ear-left")     // the window is -0.2 … 0.9
        XCTAssertEqual(zone(u: 1.00, vn: -0.50), "temple-left",  "above the window is the temple")
        XCTAssertEqual(zone(u: 1.00, vn:  1.00), "cheek-left",   "below the window, vn > 0.9")
    }

    /// A face is not a rectangle: the central column is 0.78 wide at the brow and narrows to 0.62
    /// by the mouth. A single constant could not fit both ends — 0.62 everywhere made cheek the
    /// bucket that caught the outer corner of the eye, 0.78 everywhere swallowed real cheek touches.
    func testCentralColumnNarrowsFromBrowToMouth() {
        // At vn -0.6 and above the column is at its widest, 0.78.
        XCTAssertEqual(zone(u: 0.77, vn: -0.60), "forehead")
        XCTAssertEqual(zone(u: 0.79, vn: -0.60), "temple-left")
        // At vn 0.5 and below it has narrowed to 0.62.
        XCTAssertEqual(zone(u: 0.61, vn: 0.50), "nose")
        XCTAssertEqual(zone(u: 0.63, vn: 0.50), "cheek-left")
    }

    /// Beyond the head there is no zone at all — that is what keeps a hand in the head box but off
    /// the head out of the tally.
    func testOutsideTheHead() {
        XCTAssertEqual(zone(u: 1.71, vn: 0), "outside")
        XCTAssertEqual(zone(u: 1.69, vn: 0), "ear-left")
        XCTAssertEqual(zone(u: 0, vn: 2.61), "neck", "below the head it is the neck, not outside")
    }
}
