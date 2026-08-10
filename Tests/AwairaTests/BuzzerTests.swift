import XCTest
@testable import Awaira

/// The buzz has to read as one continuous vibration that lasts exactly as long as the hand stays on
/// the face. iOS won't let a backgrounded app hold the motor on, so the effect is built out of system
/// pulses fired faster than a pulse lasts — which only works if the interval stays short.
@MainActor
final class BuzzerTests: XCTestCase {

    func testPulsesFasterThanASinglePulseLasts() {
        // A system vibration runs for roughly 0.4 s. Re-firing at or past that leaves a gap, and a
        // gap is what the user described as flickering.
        XCTAssertLessThan(Buzzer.pulseEvery, 0.4,
                          "the motor must be re-triggered before it can spin down")
    }

    func testStartAndStopAreIdempotent() {
        // Called from every processed frame, so repeat calls must not stack timers or players.
        let buzzer = Buzzer.shared
        buzzer.start()
        buzzer.start()
        buzzer.stop()
        buzzer.stop()
    }
}
