import Foundation

/// Private, on-device history for the iPhone dashboard. No camera frames or user identifiers are
/// stored here—only the aggregate numbers needed to show progress, exactly as a dashboard should.
final class MobileStatsStore {
    struct Day: Codable {
        var interruptions = 0
        var prevented = 0
        var pulls = 0
        var activeSeconds = 0.0
        var hourlyInterruptions = Array(repeating: 0, count: 24)
        /// Sustained touches by hour — the heatmap's second row. Optional in the decoder so days
        /// stored before this existed still read back, as an empty day rather than a failure.
        var hourlyPulls: [Int]?
        /// Completed touches per head zone, keyed by `ZoneHit.name` ("cheek-right", "forehead", …) —
        /// what the Today page's head draws. Optional for the same reason as `hourlyPulls`: a
        /// non-optional property's synthesized decoder fails on a missing key, and one failure here
        /// throws away the whole stored history.
        var zoneCounts: [String: Int]?
        var lastDetection: TimeInterval?

        /// The stored array padded to 24, so callers can index it by hour without checking.
        var pullsByHour: [Int] {
            guard let hourlyPulls, hourlyPulls.count == 24 else { return Array(repeating: 0, count: 24) }
            return hourlyPulls
        }

        /// The zone tally, empty rather than nil for a day stored before this existed.
        var zones: [String: Int] { zoneCounts ?? [:] }
    }

    struct DayBar: Identifiable {
        let id: String
        let date: Date
        let interruptions: Int
        let prevented: Int
        let pulls: Int
        let activeSeconds: Double
    }

    struct Snapshot {
        let today: Day
        /// Today hour by hour — one bar per hour of the day, for the heatmap.
        let todayHours: [DayBar]
        /// The same, for each day in `week`, keyed by `DayBar.id`: the heatmap follows whichever day
        /// the week strip has selected. Built here, on the capture queue, because the store itself
        /// must not be read from the main thread while detection is writing to it.
        let hoursByDay: [String: [DayBar]]
        let week: [DayBar]
        let history: [DayBar]
        let hourOfWeek: [Int]
        let weeklyTotal: Int
        let weeklyRate: Double
        /// Positive means the current seven-day rate is lower than the preceding seven days.
        let weeklyImprovement: Double?
        /// Today's touches per head zone. Today only, like the Mac's `zoneBreakdown` — the head on
        /// the Today page does not follow the week strip's selection the way the heatmap does.
        let todayZones: [String: Int]
        /// Zone totals keyed by day, so the selected day on Today drives the head as well as the chart.
        let zonesByDay: [String: [String: Int]]
        let lastDetection: Date?
    }

    private static let storageKey = "awaira.mobile.stats.v1"
    private var days: [String: Day]
    private var lastSave = Date.distantPast
    /// Read *and* written here: a store handed a throwaway suite (as tests do) must not write the
    /// real dashboard's history back into `.standard`.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: Day].self, from: data) else {
            days = [:]
            return
        }
        days = decoded
        pruneHistory()
    }

    /// Populates only the in-memory store used by App Store screenshot automation. This is never
    /// called during a normal launch, is never persisted, and cannot appear in a user's history.
    func loadScreenshotDemo(at now: Date = Date()) {
        let calendar = Calendar.current
        let recent = [24, 27, 22, 30, 25, 20, 31]
        let earlier = [36, 34, 33, 35, 31, 37, 34]
        let totals = earlier + recent
        let hours = [8, 10, 13, 15, 18, 21]
        var demo: [String: Day] = [:]

        for (index, total) in totals.enumerated() {
            guard let date = calendar.date(byAdding: .day, value: index - (totals.count - 1), to: now) else { continue }
            var interruptions = Array(repeating: 0, count: 24)
            var pulls = Array(repeating: 0, count: 24)
            for (hourIndex, hour) in hours.enumerated() {
                let value = total / hours.count + (hourIndex < total % hours.count ? 1 : 0)
                interruptions[hour] = value
                pulls[hour] = hourIndex.isMultiple(of: 2) ? max(1, value / 3) : max(0, value / 4)
            }
            let totalPulls = pulls.reduce(0, +)
            var day = Day()
            day.interruptions = total
            day.prevented = max(0, total - totalPulls)
            day.pulls = totalPulls
            day.activeSeconds = 6 * 60 * 60
            day.hourlyInterruptions = interruptions
            day.hourlyPulls = pulls
            day.lastDetection = date.addingTimeInterval(20 * 60 * 60).timeIntervalSince1970
            if index == totals.count - 1 {
                day.zoneCounts = [
                    "cheek-left": 8, "cheek-right": 10, "chin": 5,
                    "mouth": 4, "forehead": 2, "nose": 2
                ]
            }
            demo[key(for: date)] = day
        }
        days = demo
    }

    func addActive(seconds: TimeInterval, at date: Date) {
        guard seconds.isFinite, seconds > 0 else { return }
        mutateDay(for: date) { $0.activeSeconds += min(seconds, 1) }
        saveIfNeeded()
    }

    func recordDetection(at date: Date) {
        mutateDay(for: date) {
            $0.interruptions += 1
            let hour = Calendar.current.component(.hour, from: date)
            if $0.hourlyInterruptions.indices.contains(hour) { $0.hourlyInterruptions[hour] += 1 }
            $0.lastDetection = date.timeIntervalSince1970
        }
        save(force: true)
    }

    func recordOutcome(sustained: Bool, at date: Date) {
        mutateDay(for: date) {
            if sustained {
                $0.pulls += 1
                let hour = Calendar.current.component(.hour, from: date)
                var hourly = $0.pullsByHour
                if hourly.indices.contains(hour) { hourly[hour] += 1 }
                $0.hourlyPulls = hourly
            } else {
                $0.prevented += 1
            }
        }
        save(force: true)
    }

    /// One finished touch, filed under the head zone it spent the longest in. Called on the falling
    /// edge of a touch, after `recordOutcome` — and only when the classifier actually named a zone,
    /// so these totals are legitimately smaller than the day's interruption count.
    func recordZone(_ name: String, at date: Date) {
        mutateDay(for: date) {
            var zones = $0.zones
            zones[name, default: 0] += 1
            $0.zoneCounts = zones
        }
        save(force: true)
    }

    func snapshot(at now: Date = Date()) -> Snapshot {
        let calendar = Calendar.current
        let todayKey = key(for: now)
        let today = days[todayKey] ?? Day()
        let todayStart = calendar.startOfDay(for: now)
        let history = (0..<365).reversed().compactMap { offset -> DayBar? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { return nil }
            let id = key(for: date)
            let day = days[id] ?? Day()
            return DayBar(id: id, date: date, interruptions: day.interruptions,
                          prevented: day.prevented, pulls: day.pulls,
                          activeSeconds: day.activeSeconds)
        }
        let week = Array(history.suffix(7))
        let weeklyTotal = week.reduce(0) { $0 + $1.interruptions }
        let weeklySeconds = week.reduce(0.0) { $0 + $1.activeSeconds }
        let weeklyRate = Self.hourlyRate(interruptions: weeklyTotal, activeSeconds: weeklySeconds)

        let previous = (7..<14).compactMap { offset -> Day? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { return nil }
            return days[key(for: date)]
        }
        let previousTotal = previous.reduce(0) { $0 + $1.interruptions }
        let previousSeconds = previous.reduce(0.0) { $0 + $1.activeSeconds }
        let previousRate = Self.hourlyRate(interruptions: previousTotal, activeSeconds: previousSeconds)
        let improvement: Double?
        if previousSeconds >= 900, previousRate > 0 {
            improvement = (previousRate - weeklyRate) / previousRate * 100
        } else {
            improvement = nil
        }

        var hourly = Array(repeating: 0, count: 24)
        var mostRecent: TimeInterval?
        for bar in week {
            let day = days[bar.id] ?? Day()
            for index in hourly.indices where day.hourlyInterruptions.indices.contains(index) {
                hourly[index] += day.hourlyInterruptions[index]
            }
            if let last = day.lastDetection, last > (mostRecent ?? 0) { mostRecent = last }
        }
        var hoursByDay: [String: [DayBar]] = [:]
        var zonesByDay: [String: [String: Int]] = [:]
        for bar in history {
            let day = days[bar.id] ?? Day()
            hoursByDay[bar.id] = Self.hourBars(for: day,
                                               on: calendar.startOfDay(for: bar.date))
            zonesByDay[bar.id] = day.zones
        }

        return Snapshot(today: today,
                        todayHours: hoursByDay[todayKey] ?? Self.hourBars(for: today, on: todayStart),
                        hoursByDay: hoursByDay,
                        week: week, history: history, hourOfWeek: hourly, weeklyTotal: weeklyTotal,
                        weeklyRate: weeklyRate, weeklyImprovement: improvement,
                        todayZones: today.zones,
                        zonesByDay: zonesByDay,
                        lastDetection: mostRecent.map(Date.init(timeIntervalSince1970:)))
    }

    /// One day, hour by hour — what the heatmap draws. A day with nothing stored still returns 24
    /// empty hours, so the card keeps its shape from morning on.
    private static func hourBars(for day: Day, on start: Date) -> [DayBar] {
        let calendar = Calendar.current
        let pulls = day.pullsByHour
        return (0..<24).map { hour in
            let date = calendar.date(byAdding: .hour, value: hour, to: start) ?? start
            return DayBar(id: "h\(hour)", date: date,
                          interruptions: day.hourlyInterruptions.indices.contains(hour)
                                         ? day.hourlyInterruptions[hour] : 0,
                          prevented: 0,
                          pulls: pulls.indices.contains(hour) ? pulls[hour] : 0,
                          activeSeconds: 0)
        }
    }

    static func hourlyRate(interruptions: Int, activeSeconds: Double) -> Double {
        guard interruptions > 0, activeSeconds > 0 else { return 0 }
        return Double(interruptions) / (max(activeSeconds, 3600) / 3600)
    }

    private func mutateDay(for date: Date, _ body: (inout Day) -> Void) {
        let dayKey = key(for: date)
        var day = days[dayKey] ?? Day()
        body(&day)
        days[dayKey] = day
    }

    private func key(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func saveIfNeeded() {
        guard Date().timeIntervalSince(lastSave) >= 15 else { return }
        save()
    }

    private func save(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastSave) >= 1 else { return }
        lastSave = Date()
        pruneHistory()
        guard let data = try? JSONEncoder().encode(days) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func pruneHistory() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -370, to: Date()) ?? .distantPast
        let cutoffKey = key(for: cutoff)
        days = days.filter { $0.key >= cutoffKey }
    }
}
