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

    /// One App Review image per in-app purchase: the genuine paywall, scrolled so that product's
    /// card (price, period, and purchase button) is fully on screen. Prices and any free-trial
    /// offer come from StoreKit, so run this after App Store Connect is configured.
    func testCapturePremiumReviewScreens() {
        let plans = [("Monthly", "com.awaira.ios.sub.monthly"),
                     ("Yearly", "com.awaira.ios.sub.yearly"),
                     ("Lifetime", "com.awaira.app.lifetime")]
        for (name, productID) in plans {
            let app = XCUIApplication()
            app.launchArguments = ["-UITest", "-ScreenshotPaywall"]
            app.launch()

            XCTAssertTrue(app.otherElements["premiumPaywall"].waitForExistence(timeout: 5))
            // Give StoreKit a moment to replace the placeholder prices with the storefront's.
            _ = app.staticTexts["per month"].waitForExistence(timeout: 5)
            let button = app.buttons["premiumPurchaseButton.\(productID)"]
            for _ in 0..<6 where !(button.exists && button.isHittable) { app.swipeUp() }
            XCTAssertTrue(button.isHittable, "\(name) card never came fully into view")
            // "Hittable" can still mean clipped by the bottom edge; nudge the page up in short drags
            // until the purchase button sits clear of it.
            let screenBottom = app.windows.firstMatch.frame.maxY
            for _ in 0..<6 where button.frame.maxY > screenBottom - 90 {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -160)))
            }
            capture(app, named: "Awaira-\(name)-review")
            app.terminate()
        }
    }

    private func capture(_ app: XCUIApplication, named: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = named
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
