import XCTest
@testable import Awaira

/// The two runs at the foot of Today. Both are easy to get subtly wrong at their edges — a streak
/// that resets every midnight, or a quiet stretch that is really just a camera that was off.
final class MobileStreakTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "awaira.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func day(_ offset: Int, at hour: Int = 12) -> Date {
        let start = Calendar.current.startOfDay(for: Date())
        let date = Calendar.current.date(byAdding: .day, value: -offset, to: start)!
        return Calendar.current.date(byAdding: .hour, value: hour, to: date)!
    }

    // MARK: - Tracking streak

    func testConsecutiveDaysWithActivityCount() {
        let store = MobileStatsStore(defaults: defaults)
        for offset in 0..<3 { store.recordDetection(at: day(offset)) }

        XCTAssertEqual(store.snapshot().streakDays, 3)
    }

    /// The whole reason this differs from the Mac: at 9am today holds nothing yet, and a streak
    /// that read zero every morning would be measuring the clock rather than the habit.
    func testAnUntouchedTodayDoesNotBreakTheRun() {
        let store = MobileStatsStore(defaults: defaults)
        for offset in 1...4 { store.recordDetection(at: day(offset)) }

        XCTAssertEqual(store.snapshot().streakDays, 4, "the run is read from yesterday")
    }

    func testTodayJoinsTheRunOnceItHasSomething() {
        let store = MobileStatsStore(defaults: defaults)
        for offset in 1...4 { store.recordDetection(at: day(offset)) }
        store.recordDetection(at: day(0))

        XCTAssertEqual(store.snapshot().streakDays, 5)
    }

    func testAMissedDayEndsTheRun() {
        let store = MobileStatsStore(defaults: defaults)
        store.recordDetection(at: day(0))
        store.recordDetection(at: day(1))
        // Nothing on day 2 — day 3 is a separate, older run.
        store.recordDetection(at: day(3))

        XCTAssertEqual(store.snapshot().streakDays, 2)
    }

    /// A day the camera watched but recorded nothing on is still a gap: the run counts recorded
    /// approaches, which is what the Mac counts too.
    func testATrackedButEmptyDayIsNotPartOfTheRun() {
        let store = MobileStatsStore(defaults: defaults)
        store.recordDetection(at: day(1))
        for _ in 0..<600 { store.addActive(seconds: 1, at: day(2)) }
        store.recordDetection(at: day(3))

        XCTAssertEqual(store.snapshot().streakDays, 1)
    }

    func testNoHistoryIsNoStreak() {
        XCTAssertEqual(MobileStatsStore(defaults: defaults).snapshot().streakDays, 0)
    }

    // MARK: - Clean streak

    func testTheLongestQuietRunInYesterdaysActiveWindowIsFound() {
        let store = MobileStatsStore(defaults: defaults)
        for _ in 0..<1800 { store.addActive(seconds: 1, at: day(1, at: 9)) }
        // Approaches at 9, 13 and 14 — quiet at 10, 11, 12 (three hours) and nothing between 13/14.
        store.recordDetection(at: day(1, at: 9))
        store.recordDetection(at: day(1, at: 13))
        store.recordDetection(at: day(1, at: 14))

        XCTAssertEqual(store.snapshot().cleanStreakHours, 3)
    }

    /// The quiet before the first approach and after the last is not an achievement — it is the
    /// rest of the day.
    func testQuietOutsideTheActiveWindowDoesNotCount() {
        let store = MobileStatsStore(defaults: defaults)
        for _ in 0..<1800 { store.addActive(seconds: 1, at: day(1, at: 9)) }
        store.recordDetection(at: day(1, at: 9))
        store.recordDetection(at: day(1, at: 10))

        XCTAssertNil(store.snapshot().cleanStreakHours,
                     "consecutive busy hours leave no quiet run between them")
    }

    /// Under half an hour of tracking, a quiet stretch means the camera was off.
    func testABarelyTrackedYesterdayHasNoAnswer() {
        let store = MobileStatsStore(defaults: defaults)
        for _ in 0..<300 { store.addActive(seconds: 1, at: day(1, at: 9)) }
        store.recordDetection(at: day(1, at: 9))
        store.recordDetection(at: day(1, at: 15))

        XCTAssertNil(store.snapshot().cleanStreakHours)
    }

    /// Today is unfinished, so its own quiet run would climb all day on its own — the figure is
    /// deliberately about yesterday.
    func testTodaysQuietHoursAreNotTheAnswer() {
        let store = MobileStatsStore(defaults: defaults)
        for _ in 0..<3600 { store.addActive(seconds: 1, at: day(0, at: 1)) }
        store.recordDetection(at: day(0, at: 1))
        store.recordDetection(at: day(0, at: 8))

        XCTAssertNil(store.snapshot().cleanStreakHours)
    }

    // MARK: - Formatting

    func testTrackedTimeReadsAsHoursAndMinutes() {
        XCTAssertEqual(TodayStatusStrip.trackedTimeText(6 * 3600 + 36 * 60), "6h 36m")
        XCTAssertEqual(TodayStatusStrip.trackedTimeText(42 * 60), "42m")
        XCTAssertEqual(TodayStatusStrip.trackedTimeText(30), "<1 min")
        XCTAssertEqual(TodayStatusStrip.trackedTimeText(0), "<1 min")
    }
}
