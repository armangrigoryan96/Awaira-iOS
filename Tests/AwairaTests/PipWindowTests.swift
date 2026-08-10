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
        // iPhone 11, so it has to stay well past that — at *every* setting of the slider, or the
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
        let tooThin = PipWindow.preferredSize(for: .horizontal, thickness: 0)
        XCTAssertEqual(tooThin.height, PipWindow.thicknessRange.lowerBound)
        let tooThick = PipWindow.preferredSize(for: .horizontal, thickness: 5000)
        XCTAssertEqual(tooThick.height, PipWindow.thicknessRange.upperBound)
    }

    func testAskingThickerGivesAThickerBar() {
        let thin = PipWindow.preferredSize(for: .horizontal, thickness: 4)
        let thick = PipWindow.preferredSize(for: .horizontal, thickness: 40)
        XCTAssertGreaterThan(thick.height, thin.height)
        XCTAssertEqual(thin.width, thick.width, "the length is only ever the ratio's numerator")
    }

    func testTurningItUprightSwapsTheSides() {
        // Standing the thread up is the whole of what the app controls about the window's shape and
        // place — the side it lands on is remembered by iOS and can't be asked for.
        let flat = PipWindow.preferredSize(for: .horizontal, thickness: PipWindow.defaultThickness)
        let upright = PipWindow.preferredSize(for: .vertical, thickness: PipWindow.defaultThickness)
        XCTAssertEqual(flat.width, upright.height)
        XCTAssertEqual(flat.height, upright.width)
        XCTAssertGreaterThan(flat.width, flat.height)
        XCTAssertGreaterThan(upright.height, upright.width)
    }

    func testTheThicknessSurvivesARelaunch() {
        let original = PipWindow.savedThickness
        defer { PipWindow.savedThickness = original }
        PipWindow.savedThickness = 24
        XCTAssertEqual(PipWindow.savedThickness, 24)
        XCTAssertEqual(PipWindow.preferredSize(for: .horizontal).height, 24)
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
