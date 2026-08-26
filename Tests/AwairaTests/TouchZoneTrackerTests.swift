import XCTest
@testable import Awaira

/// The observer that names a finished touch. It sits downstream of `DetectionCore` and may only
/// read its decisions — every test here is about what it reports, never about what it changes.
final class TouchZoneTrackerTests: XCTestCase {

    private let size = FaceFixture.frameSize
    /// The whole frame, so the head-zone gate never gets in the way of what is being tested.
    private let wholeFrame: [Double] = [0, 0, 1, 1]

    /// A hand whose index fingertip sits at the face point (u, vn); every other joint is missing.
    private func hand(u: CGFloat, vn: CGFloat, joint: Int = 8) -> [[CGPoint]] {
        let p = FaceFixture.point(u: u, vn: vn)
        var h = Array(repeating: CGPoint(x: -1, y: -1), count: 21)
        h[joint] = CGPoint(x: p.x / size.width, y: p.y / size.height)
        return [h]
    }

    private func cheek() -> [[CGPoint]] { hand(u: 0.75, vn: 0.70) }     // cheek-left
    private func temple() -> [[CGPoint]] { hand(u: 0.85, vn: -0.50) }   // temple-left

    /// One frame through the tracker, with the face re-detected each time (the app runs the face
    /// request every third frame; holding it is covered by its own test below).
    @discardableResult
    private func step(_ tracker: TouchZoneTracker, hands: [[CGPoint]], touching: Bool,
                      zone: [Double]?? = nil, faceChecked: Bool = true) -> ZoneHit? {
        let z: [Double]? = zone ?? wholeFrame
        return tracker.update(faceFrame: faceChecked ? FaceFixture.upright() : nil,
                              faceChecked: faceChecked, hands: hands, zone: z,
                              touching: touching, frameSize: size)
    }

    /// A live label that flickers between cheek and temple is worse than none, so a zone has to
    /// repeat before `current` reports it.
    func testCurrentNeedsTwoFramesOfTheSameZone() {
        let tracker = TouchZoneTracker()
        step(tracker, hands: cheek(), touching: true)
        XCTAssertNil(tracker.current, "one frame is a fingertip skimming past")
        step(tracker, hands: cheek(), touching: true)
        XCTAssertEqual(tracker.current?.name, "cheek-left")
    }

    /// A finger wanders, so the touch is filed under wherever it dwelled longest — not wherever it
    /// happened to land first or last.
    func testTouchIsFiledUnderTheZoneItDwelledInLongest() {
        let tracker = TouchZoneTracker()
        step(tracker, hands: temple(), touching: true)
        for _ in 0..<3 { step(tracker, hands: cheek(), touching: true) }
        step(tracker, hands: temple(), touching: true)

        let finished = step(tracker, hands: [], touching: false)
        XCTAssertEqual(finished?.name, "cheek-left")
        XCTAssertEqual(tracker.lastCompleted?.name, "cheek-left")
    }

    /// Every classified frame votes, gated or not: a short touch whose zone wobbled used to finish
    /// with an empty tally, so the day's counter went up and nothing on the head did.
    func testSingleFrameTouchStillFilesAZone() {
        let tracker = TouchZoneTracker()
        step(tracker, hands: cheek(), touching: true)
        XCTAssertEqual(step(tracker, hands: [], touching: false)?.name, "cheek-left")
    }

    /// Nothing is reported until the touch is over — the head shows finished touches, not a live one.
    func testNothingIsReportedWhileTheTouchIsStillOn() {
        let tracker = TouchZoneTracker()
        for _ in 0..<5 {
            XCTAssertNil(step(tracker, hands: cheek(), touching: true))
        }
    }

    /// The tally closes on the *detector's* touch: a fingertip that dips out of the zone for a frame
    /// does not end the touch as far as the app is concerned, so it must not close the tally either.
    func testLosingTheHandForAFrameDoesNotCloseTheTouch() {
        let tracker = TouchZoneTracker()
        step(tracker, hands: cheek(), touching: true)
        XCTAssertNil(step(tracker, hands: [], touching: true), "still touching — nothing to report")
        step(tracker, hands: cheek(), touching: true)
        XCTAssertEqual(step(tracker, hands: [], touching: false)?.name, "cheek-left")
    }

    /// A touch nobody could classify — hand inside the head box but off the head — reports nothing,
    /// so the zone totals stay legitimately smaller than the day's interruption count.
    func testTouchOffTheHeadFilesNothing() {
        let tracker = TouchZoneTracker()
        for _ in 0..<4 { step(tracker, hands: hand(u: 2.0, vn: 0.0), touching: true) }
        XCTAssertNil(step(tracker, hands: [], touching: false))
        XCTAssertNil(tracker.lastCompleted)
    }

    /// The face is only re-detected every third frame, so the frame from the last face pass is held
    /// and reused in between.
    func testTheFaceFrameIsHeldBetweenFacePasses() {
        let tracker = TouchZoneTracker()
        step(tracker, hands: cheek(), touching: true, faceChecked: true)
        step(tracker, hands: cheek(), touching: true, faceChecked: false)
        step(tracker, hands: cheek(), touching: true, faceChecked: false)
        XCTAssertEqual(tracker.current?.name, "cheek-left")
        XCTAssertEqual(step(tracker, hands: [], touching: false)?.name, "cheek-left")
    }

    /// No head zone means no head to classify against, so the held face frame is stale too — and a
    /// touch that spans the gap must not be filed from what was seen before it.
    func testLosingTheHeadZoneDropsTheHeldFace() {
        let tracker = TouchZoneTracker()
        step(tracker, hands: cheek(), touching: true)
        step(tracker, hands: cheek(), touching: true, zone: .some(nil))
        XCTAssertNil(tracker.current)
        // Face gone the whole time since: nothing new can be classified, however many frames pass.
        for _ in 0..<3 {
            step(tracker, hands: cheek(), touching: true, zone: .some(nil), faceChecked: false)
        }
        XCTAssertNil(tracker.current)
    }

    /// An index finger resting near the face wins over a pinky that happens to be a few pixels
    /// closer — the fingertips are tried in priority order.
    func testIndexFingerWinsOverOtherFingertips() {
        let tracker = TouchZoneTracker()
        var hands = hand(u: 0.75, vn: 0.70, joint: 8)        // index → cheek-left
        let forehead = FaceFixture.point(u: 0.0, vn: -0.60)
        hands[0][20] = CGPoint(x: forehead.x / size.width, y: forehead.y / size.height)  // pinky
        for _ in 0..<3 { step(tracker, hands: hands, touching: true) }
        XCTAssertEqual(step(tracker, hands: [], touching: false)?.name, "cheek-left")
    }

    /// …but a pinky on its own is still a touch: the priority order picks a winner, it does not
    /// filter the other fingers out.
    func testAPinkyOnItsOwnIsStillClassified() {
        let tracker = TouchZoneTracker()
        for _ in 0..<3 { step(tracker, hands: hand(u: 0.0, vn: -0.60, joint: 20), touching: true) }
        XCTAssertEqual(step(tracker, hands: [], touching: false)?.name, "forehead")
    }
}
