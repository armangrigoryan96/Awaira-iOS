import XCTest
@testable import Awaira

@MainActor
final class TrialAccessTests: XCTestCase {

    func testASevenDayTrialShowsSixDaysOnTheFollowingCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let signUp = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 15))!
        let expiry = calendar.date(byAdding: .day, value: TrialAccess.durationDays, to: signUp)!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: signUp)!

        XCTAssertEqual(TrialAccess.calendarDaysLeft(until: expiry, now: signUp), 7)
        XCTAssertEqual(TrialAccess.calendarDaysLeft(until: expiry, now: nextDay), 6)
    }

    func testARecordedExpiredTrialCannotBeStartedAgain() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!

        XCTAssertEqual(TrialAccess.state(for: nil, now: now), .available)
        XCTAssertEqual(TrialAccess.state(for: yesterday, now: now), .expired)
    }
}
