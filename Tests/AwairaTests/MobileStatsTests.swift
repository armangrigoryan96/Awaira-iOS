import XCTest
@testable import Awaira

/// The hour-by-hour data behind the Today heatmap. Both of its rows come from the same store, and
/// the "Interrupted" one is the newer of the two — it is the one that can silently stay at zero.
final class MobileStatsTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // A throwaway suite, so a test never reads or overwrites the real dashboard's history.
        suiteName = "awaira.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func today(at hour: Int) -> Date {
        let start = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .hour, value: hour, to: start)!
    }

    func testApproachesAndSustainedTouchesLandInTheirOwnHour() {
        let store = MobileStatsStore(defaults: defaults)
        store.recordDetection(at: today(at: 9))
        store.recordDetection(at: today(at: 14))
        store.recordDetection(at: today(at: 14))
        store.recordOutcome(sustained: true, at: today(at: 14))
        store.recordOutcome(sustained: false, at: today(at: 9))   // released — not an interruption

        let hours = store.snapshot().todayHours
        XCTAssertEqual(hours.count, 24)
        XCTAssertEqual(hours[9].interruptions, 1)
        XCTAssertEqual(hours[9].pulls, 0, "a released touch must not show in the Interrupted row")
        XCTAssertEqual(hours[14].interruptions, 2)
        XCTAssertEqual(hours[14].pulls, 1)
        XCTAssertEqual(hours.reduce(0) { $0 + $1.pulls }, 1)
    }

    /// The heatmap follows the week strip, so every day it can show has to have its own hours.
    func testEveryDayInTheWeekHasHours() {
        let store = MobileStatsStore(defaults: defaults)
        store.recordDetection(at: today(at: 8))

        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.week.count, 7)
        for day in snapshot.week {
            XCTAssertEqual(snapshot.hoursByDay[day.id]?.count, 24, "no hours for \(day.id)")
        }
        XCTAssertEqual(snapshot.hoursByDay[snapshot.week.last!.id]?[8].interruptions, 1)
    }

    /// Days written before `hourlyPulls` existed still have to decode — as an empty row, not a
    /// failure that would drop the whole history.
    func testHistoryWrittenBeforeHourlyPullsStillDecodes() {
        let key = "awaira.mobile.stats.v1"
        let dayKey: String = {
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        }()
        let legacy = """
        {"\(dayKey)":{"interruptions":3,"prevented":1,"pulls":2,"activeSeconds":600,\
        "hourlyInterruptions":[\(Array(repeating: "0", count: 10).joined(separator: ","))\
        ,3,\(Array(repeating: "0", count: 13).joined(separator: ","))]}}
        """
        defaults.set(Data(legacy.utf8), forKey: key)

        let snapshot = MobileStatsStore(defaults: defaults).snapshot()
        XCTAssertEqual(snapshot.today.interruptions, 3)
        XCTAssertEqual(snapshot.todayHours[10].interruptions, 3)
        XCTAssertEqual(snapshot.todayHours[10].pulls, 0)
        XCTAssertEqual(snapshot.todayZones, [:], "a day stored before zones existed has none")
    }

    /// The head on Today counts finished touches per zone, and it reads them off the snapshot — the
    /// store itself is written from the capture queue and must never be read by a view.
    func testZonesAccumulateAndRideOnTheSnapshot() {
        let store = MobileStatsStore(defaults: defaults)
        store.recordZone("cheek-right", at: today(at: 9))
        store.recordZone("cheek-right", at: today(at: 14))
        store.recordZone("forehead", at: today(at: 14))

        XCTAssertEqual(store.snapshot().todayZones, ["cheek-right": 2, "forehead": 1])
    }

    /// Zones are the day's own tally, so yesterday's touches must not leak into today's head.
    func testZonesAreScopedToTheirDay() {
        let store = MobileStatsStore(defaults: defaults)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today(at: 12))!
        store.recordZone("chin", at: yesterday)
        store.recordZone("nose", at: today(at: 12))

        XCTAssertEqual(store.snapshot().todayZones, ["nose": 1])
    }

    /// The hour chart's rate mode divides an hour's count by the time tracked *in that hour*, so
    /// the seconds have to be filed by hour and not only into the day's total.
    func testTrackedSecondsLandInTheirOwnHour() {
        let store = MobileStatsStore(defaults: defaults)
        for _ in 0..<600 { store.addActive(seconds: 1, at: today(at: 9)) }
        for _ in 0..<300 { store.addActive(seconds: 1, at: today(at: 14)) }

        let hours = store.snapshot().todayHours
        XCTAssertEqual(hours[9].activeSeconds, 600, accuracy: 0.001)
        XCTAssertEqual(hours[14].activeSeconds, 300, accuracy: 0.001)
        XCTAssertEqual(hours[10].activeSeconds, 0, accuracy: 0.001)
        // And the day's own total still adds up to the same tracking.
        XCTAssertEqual(store.snapshot().today.activeSeconds, 900, accuracy: 0.001)
    }

    /// An hour bucket warms up in a quarter of an hour, not a whole one — the day's floor would
    /// flatten every hour bar back into its raw count.
    func testAnHourRateUsesTheHourWarmUp() {
        // Ten approaches in half an hour of tracking is twenty an hour.
        XCTAssertEqual(MobileStatsStore.hourlyRate(interruptions: 10, activeSeconds: 1800,
                                                   warmUp: MobileStatsStore.hourWarmUp),
                       20, accuracy: 0.001)
        // Under the warm-up the divisor stops shrinking, so a young hour reads as "approaches in
        // the last quarter hour" — 3 in the first minute is 12/hr, not the 180/hr a literal
        // division would print.
        XCTAssertEqual(MobileStatsStore.hourlyRate(interruptions: 3, activeSeconds: 60,
                                                   warmUp: MobileStatsStore.hourWarmUp),
                       12, accuracy: 0.001)
        // The day's default is unchanged for every existing caller.
        XCTAssertEqual(MobileStatsStore.hourlyRate(interruptions: 10, activeSeconds: 1800),
                       10, accuracy: 0.001)
    }

    /// Written before `hourlyActiveSeconds` existed, a day still has to decode — with its hours
    /// untracked rather than as a failure that would drop the whole history.
    func testHistoryWrittenBeforeHourlySecondsStillDecodes() {
        let key = "awaira.mobile.stats.v1"
        let dayKey: String = {
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        }()
        let legacy = """
        {"\(dayKey)":{"interruptions":4,"prevented":0,"pulls":1,"activeSeconds":1200,\
        "hourlyInterruptions":[\(Array(repeating: "0", count: 24).joined(separator: ","))],\
        "hourlyPulls":[\(Array(repeating: "0", count: 24).joined(separator: ","))],\
        "zoneCounts":{"chin":1}}}
        """
        defaults.set(Data(legacy.utf8), forKey: key)

        let store = MobileStatsStore(defaults: defaults)
        XCTAssertEqual(store.snapshot().today.interruptions, 4, "the stored day survived")
        XCTAssertEqual(store.snapshot().today.activeSeconds, 1200, accuracy: 0.001)
        XCTAssertEqual(store.snapshot().todayHours[9].activeSeconds, 0,
                       "an hour stored before this existed reads as untracked")

        // And it takes hourly seconds from here on without losing the day total it already had.
        store.addActive(seconds: 1, at: today(at: 9))
        XCTAssertEqual(store.snapshot().today.activeSeconds, 1201, accuracy: 0.001)
        XCTAssertEqual(store.snapshot().todayHours[9].activeSeconds, 1, accuracy: 0.001)
    }

    /// Written before `zoneCounts` existed, a day still has to decode — as a day with no zones, not
    /// as a failure that would drop the whole history.
    func testHistoryWrittenBeforeZoneCountsStillDecodes() {
        let key = "awaira.mobile.stats.v1"
        let dayKey: String = {
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        }()
        let legacy = """
        {"\(dayKey)":{"interruptions":5,"prevented":2,"pulls":3,"activeSeconds":900,\
        "hourlyInterruptions":[\(Array(repeating: "0", count: 24).joined(separator: ","))],\
        "hourlyPulls":[\(Array(repeating: "0", count: 24).joined(separator: ","))]}}
        """
        defaults.set(Data(legacy.utf8), forKey: key)

        let store = MobileStatsStore(defaults: defaults)
        XCTAssertEqual(store.snapshot().today.interruptions, 5, "the stored day survived")
        XCTAssertEqual(store.snapshot().todayZones, [:])

        // And it takes zones from here on without losing what it already had.
        store.recordZone("temple-left", at: Date())
        XCTAssertEqual(store.snapshot().today.interruptions, 5)
        XCTAssertEqual(store.snapshot().todayZones, ["temple-left": 1])
    }
}
