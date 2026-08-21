import XCTest
@testable import Awaira

/// The floating window is a means, not a view: it keeps the app on screen so iOS allows the camera.
/// So the only thing worth pinning is what decides how much of the screen it takes.
final class PipWindowTests: XCTestCase {

    func testWeAskForAThreadNotARectangle() {
        // `preferredContentSize` is the one size AVKit takes from us — the sample-buffer window it
        // replaced ignored the frames' shape and stayed a tall portrait rectangle. And since AVKit
        // takes only the ratio and picks its own scale (the window comes out the full width of the
        // screen), the ratio is the only lever on how tall the bar is: 8:1 gave ~48 pt on an
        // iPhone 11, so it has to stay well past that — at every setting of the slider, or the
        // thickest one turns the thread into a slab.
        for thickness in [PipWindow.thicknessRange.lowerBound,
                          PipWindow.defaultThickness,
                          PipWindow.thicknessRange.upperBound] {
            XCTAssertGreaterThanOrEqual(PipWindow.aspectRatio(thickness: thickness), 16,
                                        "the window has to stay far wider than it is tall")
        }
    }

    func testThePreferredThicknessIsSymbolic() {
        // Only the ratio travels, but a small number keeps this readable as "a thread".
        // The length is free — it's just the numerator.
        XCTAssertLessThanOrEqual(PipWindow.defaultThickness, 30)
    }

    /// The slider hands us whatever the user drags it to, and `savedThickness` hands us whatever is
    /// in `UserDefaults` — including, on an older install, nothing at all.
    func testAThicknessOutsideTheRangeCannotReachTheWindow() {
        let tooThin = PipWindow.preferredSize(thickness: 0)
        XCTAssertEqual(tooThin.width, PipWindow.thicknessRange.lowerBound)
        let tooThick = PipWindow.preferredSize(thickness: 5000)
        XCTAssertEqual(tooThick.width, PipWindow.thicknessRange.upperBound)
    }

    func testAskingThickerGivesAThickerBar() {
        let thin = PipWindow.preferredSize(thickness: 4)
        let thick = PipWindow.preferredSize(thickness: 40)
        XCTAssertGreaterThan(thick.width, thin.width)
        XCTAssertEqual(thin.height, thick.height, "the length is only ever the ratio's numerator")
    }

    func testTheThicknessSurvivesARelaunch() {
        let original = PipWindow.savedThickness
        defer { PipWindow.savedThickness = original }
        PipWindow.savedThickness = 24
        XCTAssertEqual(PipWindow.savedThickness, 24)
        XCTAssertEqual(PipWindow.preferredSize().width, 24)
    }

    func testTheBarCarriesTheRedFramesJob() {
        // Away: nothing to report, and black is what makes the window easy to ignore.
        XCTAssertEqual(PipWindow.tint(forLevel: 0), .idle)
        // A touch has to be visible in the window, not just felt three seconds later.
        XCTAssertEqual(PipWindow.tint(forLevel: 1), .touching)
        XCTAssertEqual(PipWindow.tint(forLevel: 2), .touching)
        // Three seconds in — this is the level that also buzzes.
        XCTAssertEqual(PipWindow.tint(forLevel: 3), .sustained)
    }

    func testAlertColoursAreRedAndEscalate() {
        var idle = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        var touching = idle
        var sustained = idle
        PipWindow.colour(for: .idle).getRed(&idle.0, green: &idle.1, blue: &idle.2, alpha: &idle.3)
        PipWindow.colour(for: .touching).getRed(&touching.0, green: &touching.1, blue: &touching.2,
                                                alpha: &touching.3)
        PipWindow.colour(for: .sustained).getRed(&sustained.0, green: &sustained.1, blue: &sustained.2,
                                                 alpha: &sustained.3)
        XCTAssertGreaterThan(touching.0, idle.0)
        XCTAssertGreaterThan(sustained.0, touching.0, "the three-second mark has to look worse")
        XCTAssertGreaterThan(touching.0, touching.1, "and both have to read as red")
    }
}
