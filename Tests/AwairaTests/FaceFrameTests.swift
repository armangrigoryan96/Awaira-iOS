import XCTest
@testable import Awaira

/// A synthetic face in display pixels, used by every test that needs a `FaceFrame`.
///
/// Deliberately round numbers: eyes 80 px apart on a level line, the mouth 88 px below them, so
/// `ipd` is 80 and `mouthV` is exactly 1.1 — the middle of the range Vision reports for a real
/// face. That makes `point(u:vn:)` an exact inverse of the classifier's own projection, so a test
/// can name the coordinates the thresholds are written in instead of guessing pixels.
enum FaceFixture {
    static let frameSize = CGSize(width: 480, height: 640)
    static let origin = CGPoint(x: 240, y: 240)
    static let ipd: CGFloat = 80
    static let mouthV: CGFloat = 1.1

    static func upright() -> FaceFrame {
        FaceFrame(leftEye: CGPoint(x: 280, y: 240), rightEye: CGPoint(x: 200, y: 240),
                  noseTip: CGPoint(x: 240, y: 300),
                  mouthLeft: CGPoint(x: 270, y: 328), mouthRight: CGPoint(x: 210, y: 328))!
    }

    /// The same face with the head rolled by `degrees` about the bridge of the nose.
    static func rolled(_ degrees: CGFloat) -> FaceFrame {
        FaceFrame(leftEye: rotate(CGPoint(x: 280, y: 240), by: degrees),
                  rightEye: rotate(CGPoint(x: 200, y: 240), by: degrees),
                  noseTip: rotate(CGPoint(x: 240, y: 300), by: degrees),
                  mouthLeft: rotate(CGPoint(x: 270, y: 328), by: degrees),
                  mouthRight: rotate(CGPoint(x: 210, y: 328), by: degrees))!
    }

    /// The display pixel at face coordinates (u, vn) on the upright face — u in interocular units,
    /// vn in fractions of the eye→mouth distance (0 = eye line, 1 = mouth).
    static func point(u: CGFloat, vn: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + u * ipd, y: origin.y + vn * mouthV * ipd)
    }

    static func rotate(_ p: CGPoint, by degrees: CGFloat) -> CGPoint {
        let a = degrees * .pi / 180
        let dx = p.x - origin.x, dy = p.y - origin.y
        return CGPoint(x: origin.x + dx * cos(a) - dy * sin(a),
                       y: origin.y + dx * sin(a) + dy * cos(a))
    }
}

/// The zone classifier: does a fingertip at a known place on the head get the right name?
///
/// Every expectation here is the *Mac's* behaviour — `FaceFrame.swift` is a verbatim copy — so a
/// failure means the two platforms have drifted apart, not that the phone needs tuning.
final class FaceFrameTests: XCTestCase {

    private func name(_ face: FaceFrame, u: CGFloat, vn: CGFloat) -> String {
        face.classify(FaceFixture.point(u: u, vn: vn), fingertipIndex: 8).name
    }

    /// Every zone the classifier can produce, at a point that plainly belongs to it.
    func testCanonicalPointsOfEveryZone() {
        let face = FaceFixture.upright()
        XCTAssertEqual(name(face, u:  0.00, vn: -1.70), "topofhead")
        XCTAssertEqual(name(face, u:  0.10, vn: -1.30), "hair-left")
        XCTAssertEqual(name(face, u: -0.10, vn: -1.30), "hair-right")
        XCTAssertEqual(name(face, u:  0.00, vn: -0.60), "forehead")
        XCTAssertEqual(name(face, u:  0.85, vn: -0.50), "temple-left")
        XCTAssertEqual(name(face, u: -0.85, vn: -0.50), "temple-right")
        XCTAssertEqual(name(face, u:  0.30, vn:  0.00), "eye-left")
        XCTAssertEqual(name(face, u: -0.30, vn:  0.00), "eye-right")
        XCTAssertEqual(name(face, u:  1.00, vn:  0.30), "ear-left")
        XCTAssertEqual(name(face, u: -1.00, vn:  0.30), "ear-right")
        XCTAssertEqual(name(face, u:  0.00, vn:  0.50), "nose")
        XCTAssertEqual(name(face, u:  0.75, vn:  0.70), "cheek-left")
        XCTAssertEqual(name(face, u: -0.75, vn:  0.70), "cheek-right")
        XCTAssertEqual(name(face, u:  0.00, vn:  1.00), "mouth")
        XCTAssertEqual(name(face, u:  0.00, vn:  1.60), "chin")
        XCTAssertEqual(name(face, u:  0.00, vn:  2.20), "neck")
        XCTAssertEqual(name(face, u:  2.00, vn:  0.00), "outside")
    }

    /// The whole reason the classifier uses landmarks rather than the face box: tilt the head and
    /// every zone still lands where it did. An axis-aligned rectangle could not do this.
    ///
    /// The *zone* is what rolls with the head — the side does not, and must not: it is named from
    /// the display x so the number lights up on the side of the artwork the viewer sees the hand on.
    /// Tip the head far enough and a point just off the midline genuinely crosses to the other side
    /// of the screen.
    func testRolledHeadClassifiesTheSameWay() {
        let upright = FaceFixture.upright()
        for degrees in [-30.0, -12.0, 12.0, 30.0] as [CGFloat] {
            let rolled = FaceFixture.rolled(degrees)
            for (u, vn) in [(0.0, -1.70), (0.10, -1.30), (0.0, -0.60), (0.85, -0.50),
                            (0.30, 0.0), (1.00, 0.30), (0.0, 0.50), (0.75, 0.70),
                            (0.0, 1.00), (0.0, 1.60)] as [(CGFloat, CGFloat)] {
                let p = FaceFixture.point(u: u, vn: vn)
                XCTAssertEqual(rolled.classify(FaceFixture.rotate(p, by: degrees),
                                               fingertipIndex: 8).zone,
                               upright.classify(p, fingertipIndex: 8).zone,
                               "(u \(u), vn \(vn)) at \(degrees)°")
            }
        }
    }

    /// The side is named the way the person feels it, so the head artwork reads like a mirror: the
    /// camera hands over an already-mirrored selfie image, so screen-left is the person's right.
    /// If this ever flips, the numbers appear on the wrong side of the head on Today.
    func testSideIsMirrored() {
        let face = FaceFixture.upright()
        XCTAssertEqual(name(face, u:  0.75, vn: 0.70), "cheek-left",
                       "a point to the right of the screen is the person's left cheek")
        XCTAssertEqual(name(face, u: -0.75, vn: 0.70), "cheek-right")
    }

    /// The zones with no side must not grow one — `TouchZonesCard` looks them up by the bare name.
    func testCentralZonesCarryNoSide() {
        let face = FaceFixture.upright()
        for (u, vn) in [(0.0, -1.70), (0.0, -0.60), (0.0, 0.50), (0.0, 1.00), (0.0, 1.60),
                        (0.0, 2.20)] as [(CGFloat, CGFloat)] {
            XCTAssertFalse(name(face, u: u, vn: vn).contains("-"), "vn \(vn) grew a side")
        }
    }

    /// A face too small, or with nonsense geometry, must be refused rather than classified against.
    func testDegenerateFacesAreRejected() {
        XCTAssertNil(FaceFrame(leftEye: CGPoint(x: 241, y: 240), rightEye: CGPoint(x: 239, y: 240),
                               noseTip: CGPoint(x: 240, y: 244),
                               mouthLeft: CGPoint(x: 242, y: 246), mouthRight: CGPoint(x: 238, y: 246)),
                     "an interocular distance under 4 px is not something to reason about")
        XCTAssertNil(FaceFrame(leftEye: CGPoint(x: 280, y: 240), rightEye: CGPoint(x: 200, y: 240),
                               noseTip: CGPoint(x: 240, y: 260),
                               mouthLeft: CGPoint(x: 270, y: 264), mouthRight: CGPoint(x: 210, y: 264)),
                     "a mouth barely below the eyes means an extreme angle or a bad detect")
    }
}
