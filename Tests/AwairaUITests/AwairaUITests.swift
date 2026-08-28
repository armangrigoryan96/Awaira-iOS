import XCTest

/// Smoke test: the app launches, draws its HUD, and survives a background/foreground round trip.
/// The simulator has no camera, so it launches with `-UITest` and the session is never started.
final class AwairaUITests: XCTestCase {

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITest"]
        // The camera permission alert shouldn't appear in this mode, but if it ever does, dismiss
        // it rather than hanging the test.
        addUIInterruptionMonitor(withDescription: "camera permission") { alert in
            for label in ["Allow", "OK", "Разрешить"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
        return app
    }

    func testLaunchesAndShowsTheCounter() {
        let app = launchApp()
        // "approaches today" on the Today card — the count alone, with its label beside it. A
        // count with nothing recorded is 0; the em-dash belongs to the per-hour rate above it,
        // which has no meaning until a minute has been tracked.
        let counter = app.staticTexts["todayCount"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10))
        XCTAssertEqual(counter.label, "0")
        XCTAssertTrue(app.buttons["settingsToggle"].exists)
        // The camera lives in the header pill, and the simulator never starts it. The pill is a
        // button, so its state reads off the control rather than off a child text: SwiftUI merges a
        // button's children into one element, which is what VoiceOver should announce.
        XCTAssertEqual(app.buttons["toggleCamera"].label, "Camera off")
    }

    func testSurvivesBackgrounding() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["todayCount"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["todayCount"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
    }
}
