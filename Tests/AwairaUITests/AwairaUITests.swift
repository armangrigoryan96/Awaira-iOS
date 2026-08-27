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
        // The Today awareness figure remains present before the detector has collected a baseline.
        let counter = app.staticTexts["todayCount"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10))
        XCTAssertEqual(counter.label, "—")
        XCTAssertTrue(app.buttons["settingsToggle"].exists)
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
