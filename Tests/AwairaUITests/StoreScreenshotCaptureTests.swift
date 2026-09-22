import XCTest

final class StoreScreenshotCaptureTests: XCTestCase {
    func testCaptureStoreScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-ScreenshotDemo"]
        app.launch()

        capture(app, named: "01-today-demo")
        app.buttons["tab.Patterns"].tap()
        capture(app, named: "02-patterns-demo")
        app.buttons["tab.Learn"].tap()
        capture(app, named: "03-learn-demo")
    }

    func testCaptureLifetimeUnlockReviewScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-ScreenshotPaywall"]
        app.launch()

        XCTAssertTrue(app.otherElements["premiumPaywall"].waitForExistence(timeout: 3))
        capture(app, named: "04-lifetime-unlock-review")
    }

    private func capture(_ app: XCUIApplication, named: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = named
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
