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
}
