import XCTest
final class ZZD: XCTestCase {
    func testShots() {
        let app = XCUIApplication(); app.launchArguments += ["-UITest"]; app.launch()
        let dir = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-grigoryan-Desktop-Projects-Awaira/3ffca7ed-2e13-4c4c-b5c0-1b233de6741a/scratchpad")
        func shot(_ n: String) {
            Thread.sleep(forTimeInterval: 1.3)
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("g-\(n).png"))
        }
        for t in ["Today","Patterns","Journal"] {
            let b = app.buttons["tab.\(t)"]; if b.waitForExistence(timeout: 10) { b.tap() }; shot(t)
        }
    }
}
