import XCTest
@testable import Awaira

/// The overlay has to crop exactly like the aspect-filling preview layer, or the head-zone box
/// drifts away from the head it's drawn around.
final class PreviewGeometryTests: XCTestCase {

    /// A portrait phone screen and a portrait 480×640 buffer (VGA rotated upright).
    private let viewSize = CGSize(width: 390, height: 844)
    private let bufferAspect: CGFloat = 480.0 / 640.0

    func testFilledRectCoversTheViewAndOverflowsOnOneAxis() {
        let r = PreviewGeometry.filledRect(bufferAspect: bufferAspect, viewSize: viewSize)
        XCTAssertLessThanOrEqual(r.minX, 0)
        XCTAssertLessThanOrEqual(r.minY, 0)
        XCTAssertGreaterThanOrEqual(r.maxX, viewSize.width)
        XCTAssertGreaterThanOrEqual(r.maxY, viewSize.height)
        // A 3:4 buffer is relatively wide next to a 390×844 screen, so heights match and the
        // sides are cropped: 844 × 0.75 = 633 pt of buffer squeezed into 390 pt of screen.
        XCTAssertEqual(r.height, viewSize.height, accuracy: 1e-6)
        XCTAssertEqual(r.width, 633, accuracy: 1e-6)
        XCTAssertEqual(r.midX, viewSize.width / 2, accuracy: 1e-6, "the crop is centered")
    }

    func testWideBufferOverflowsHorizontally() {
        let r = PreviewGeometry.filledRect(bufferAspect: 16.0 / 9.0, viewSize: viewSize)
        XCTAssertEqual(r.height, viewSize.height, accuracy: 1e-6)
        XCTAssertGreaterThan(r.width, viewSize.width)
        XCTAssertEqual(r.midX, viewSize.width / 2, accuracy: 1e-6, "the crop is centered")
    }

    func testCenterMapsToCenter() {
        let p = PreviewGeometry.point(CGPoint(x: 0.5, y: 0.5),
                                      bufferAspect: bufferAspect, viewSize: viewSize)
        XCTAssertEqual(p.x, viewSize.width / 2, accuracy: 1e-6)
        XCTAssertEqual(p.y, viewSize.height / 2, accuracy: 1e-6)
    }

    func testMatchingAspectMapsOneToOne() {
        let square = CGSize(width: 300, height: 300)
        let p = PreviewGeometry.point(CGPoint(x: 0.25, y: 0.75), bufferAspect: 1, viewSize: square)
        XCTAssertEqual(p.x, 75, accuracy: 1e-6)
        XCTAssertEqual(p.y, 225, accuracy: 1e-6)
    }

    func testZoneRectIsNormalizedAndOrdered() {
        guard let r = PreviewGeometry.rect(zone: [0.34, 0.2125, 0.66, 0.6625],
                                           bufferAspect: bufferAspect, viewSize: viewSize) else {
            return XCTFail("expected a rect")
        }
        XCTAssertGreaterThan(r.width, 0)
        XCTAssertGreaterThan(r.height, 0)
        XCTAssertEqual(r.midX, viewSize.width / 2, accuracy: 1e-6, "a centered zone stays centered")
    }

    func testMalformedZoneIsIgnored() {
        XCTAssertNil(PreviewGeometry.rect(zone: [0.1, 0.2], bufferAspect: bufferAspect,
                                          viewSize: viewSize))
    }

    func testDegenerateInputsDoNotCrash() {
        let r = PreviewGeometry.filledRect(bufferAspect: 0, viewSize: .zero)
        XCTAssertEqual(r, .zero)
    }
}
