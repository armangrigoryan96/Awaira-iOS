import XCTest
final class ZZT: XCTestCase {
    func testDump() {
        let app = XCUIApplication(); app.launchArguments += ["-UITest"]; app.launch()
        Thread.sleep(forTimeInterval: 4)
        try? app.debugDescription.write(to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-grigoryan-Desktop-Projects-Awaira/3ffca7ed-2e13-4c4c-b5c0-1b233de6741a/scratchpad/tree2.txt"), atomically: true, encoding: .utf8)
    }
}
