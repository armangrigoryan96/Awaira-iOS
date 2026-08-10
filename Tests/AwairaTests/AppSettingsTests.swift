import XCTest
@testable import Awaira

/// How long the app waits before reacting: it has to stay inside its range however it's set, and
/// it has to keep the escalation ladder in order.
final class AppSettingsTests: XCTestCase {

    private var settings: AppSettings!

    override func setUp() {
        super.setUp()
        // Start from the shipped default rather than whatever a previous run left behind.
        UserDefaults.standard.removeObject(forKey: "buzzAfterSeconds")
        settings = AppSettings()
    }

    func testTheDefaultIsTheValueItReplaced() {
        XCTAssertEqual(settings.buzzAfter, 3.0)     // ContentView's old `level3After = 3.0`
        XCTAssertEqual(settings.lingerAfter, 2.0)   // DetectionCore.Config().level2After
    }

    func testValuesOutsideTheRangeAreClamped() {
        settings.buzzAfter = 0
        XCTAssertEqual(settings.buzzAfter, AppSettings.buzzAfterRange.lowerBound)
        settings.buzzAfter = 60
        XCTAssertEqual(settings.buzzAfter, AppSettings.buzzAfterRange.upperBound)
    }

    /// Level 2 is invisible on the phone, but a level 2 that arrived *after* level 3 would make
    /// `DetectionCore.process` report the ladder out of order.
    func testLingerAlwaysComesBeforeTheBuzz() {
        for delay in stride(from: AppSettings.buzzAfterRange.lowerBound,
                            through: AppSettings.buzzAfterRange.upperBound,
                            by: AppSettings.buzzAfterStep) {
            settings.buzzAfter = delay
            XCTAssertLessThan(settings.lingerAfter, settings.buzzAfter, "at \(delay) s")
        }
    }

    func testTheChoiceSurvivesARelaunch() {
        settings.buzzAfter = 5.5
        XCTAssertEqual(AppSettings().buzzAfter, 5.5)
    }
}
