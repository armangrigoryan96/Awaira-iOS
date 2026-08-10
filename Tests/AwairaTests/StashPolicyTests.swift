import XCTest
@testable import Awaira

/// The window has to come back out of the screen edge — that's the only state in which iOS lets the
/// camera keep running, so there is nothing the app can do while it stays there.
final class StashPolicyTests: XCTestCase {

    func testFirstAttemptIsTheCheapOne() {
        var policy = StashPolicy()
        // The soft attempt keeps the size the user pinched the window to, so it goes first.
        XCTAssertEqual(policy.actionOnSuspend(at: 100), .soft)
    }

    func testWaitsBeforeDecidingTheSoftAttemptFailed() {
        var policy = StashPolicy()
        XCTAssertEqual(policy.actionOnSuspend(at: 100), .soft)
        // The poll runs every 0.15 s; the next tick is too early to know anything.
        XCTAssertEqual(policy.actionOnSuspend(at: 100.15), .wait)
        XCTAssertEqual(policy.actionOnSuspend(at: 100.3), .restart)
    }

    func testItNeverStopsPullingTheWindowBack() {
        var policy = StashPolicy()
        XCTAssertEqual(policy.actionOnSuspend(at: 100), .soft)
        XCTAssertEqual(policy.actionOnSuspend(at: 101), .restart)
        XCTAssertEqual(policy.actionOnSuspend(at: 102), .restart)
        // Stashed the app is blind, so there is no attempt count worth honouring — a window left in
        // the wall is strictly worse than one that keeps coming back out.
        XCTAssertEqual(policy.actionOnSuspend(at: 103), .restart)
        XCTAssertEqual(policy.actionOnSuspend(at: 200), .restart)
    }

    func testResetStartsFromSoftAgain() {
        var policy = StashPolicy()
        XCTAssertEqual(policy.actionOnSuspend(at: 100), .soft)
        XCTAssertEqual(policy.actionOnSuspend(at: 101), .restart)
        // The window is back on screen — a later stash is a fresh problem.
        policy.reset()
        XCTAssertEqual(policy.actionOnSuspend(at: 150), .soft)
    }

    func testRetriesArePacedNotSpun() {
        var policy = StashPolicy()
        policy.softRetryAfter = 1
        XCTAssertEqual(policy.actionOnSuspend(at: 100), .soft)
        // Never giving up only works because attempts are spaced out — the 0.3 s poll must not turn
        // into a stop/start on every tick.
        XCTAssertEqual(policy.actionOnSuspend(at: 100.6), .wait)
        XCTAssertEqual(policy.actionOnSuspend(at: 101), .restart)
        XCTAssertEqual(policy.actionOnSuspend(at: 101.5), .wait)
    }
}
