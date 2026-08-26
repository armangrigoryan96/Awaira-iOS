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
