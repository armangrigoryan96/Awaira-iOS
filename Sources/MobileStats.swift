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
        /// Tracked seconds by hour — what turns the hour chart's counts into a rate. Optional for
        /// the same reason as `hourlyPulls`: a day stored before this existed reads back as an
        /// untracked one rather than throwing away the whole history.
        var hourlyActiveSeconds: [Double]?
        /// Answers to "What was happening?", keyed by `MobileContextChoice.id`. Optional for the
        /// same reason as the fields above.
        var contextCounts: [String: Int]?
        var lastDetection: TimeInterval?

        /// The stored array padded to 24, so callers can index it by hour without checking.
        var pullsByHour: [Int] {
            guard let hourlyPulls, hourlyPulls.count == 24 else { return Array(repeating: 0, count: 24) }
            return hourlyPulls
        }

        /// The same, for tracked seconds.
        var activeSecondsByHour: [Double] {
            guard let hourlyActiveSeconds, hourlyActiveSeconds.count == 24 else {
                return Array(repeating: 0, count: 24)
            }
            return hourlyActiveSeconds
        }

        /// The zone tally, empty rather than nil for a day stored before this existed.
        var zones: [String: Int] { zoneCounts ?? [:] }

        /// The same, for context answers.
        var contexts: [String: Int] { contextCounts ?? [:] }
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
        let hourOfWeek: [Int]
        let weeklyTotal: Int
        let weeklyRate: Double
        /// Positive means the current seven-day rate is lower than the preceding seven days.
        let weeklyImprovement: Double?
        /// Today's touches per head zone. Today only, like the Mac's `zoneBreakdown` — the head on
        /// the Today page does not follow the week strip's selection the way the heatmap does.
        let todayZones: [String: Int]
        /// Today's answers to "What was happening?", scoped the same way as `todayZones`.
        let todayContexts: [String: Int]
        /// Consecutive days with at least one recorded approach.
        let streakDays: Int
        /// Yesterday's longest run of hours with nothing recorded, or `nil` when yesterday was not
        /// tracked enough to say.
        let cleanStreakHours: Int?
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

    func addActive(seconds: TimeInterval, at date: Date) {
        guard seconds.isFinite, seconds > 0 else { return }
        let capped = min(seconds, 1)
        mutateDay(for: date) {
            $0.activeSeconds += capped
            // The same second, also filed under its hour, so the chart can divide a count by the
            // time actually spent tracking that hour rather than by the whole day.
            let hour = Calendar.current.component(.hour, from: date)
            var hourly = $0.activeSecondsByHour
            if hourly.indices.contains(hour) { hourly[hour] += capped }
            $0.hourlyActiveSeconds = hourly
        }
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

    /// One answer to "What was happening?", filed under the day the *touch* happened on — not the
    /// day the user got round to answering, which can be the next one either side of midnight.
    func recordContext(_ id: String, at date: Date) {
        mutateDay(for: date) {
            var contexts = $0.contexts
            contexts[id, default: 0] += 1
            $0.contextCounts = contexts
        }
        save(force: true)
    }

    func snapshot(at now: Date = Date()) -> Snapshot {
        let calendar = Calendar.current
        let todayKey = key(for: now)
        let today = days[todayKey] ?? Day()
        let todayStart = calendar.startOfDay(for: now)
        let week = (0..<7).reversed().compactMap { offset -> DayBar? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { return nil }
            let id = key(for: date)
            let day = days[id] ?? Day()
            return DayBar(id: id, date: date, interruptions: day.interruptions,
                          prevented: day.prevented, pulls: day.pulls,
                          activeSeconds: day.activeSeconds)
        }
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
        for bar in week {
            hoursByDay[bar.id] = Self.hourBars(for: days[bar.id] ?? Day(),
                                               on: calendar.startOfDay(for: bar.date))
        }

        return Snapshot(today: today,
                        todayHours: hoursByDay[todayKey] ?? Self.hourBars(for: today, on: todayStart),
                        hoursByDay: hoursByDay,
                        week: week, hourOfWeek: hourly, weeklyTotal: weeklyTotal,
                        weeklyRate: weeklyRate, weeklyImprovement: improvement,
                        todayZones: today.zones,
                        todayContexts: today.contexts,
                        streakDays: streakValue(todayStart: todayStart, calendar: calendar),
                        cleanStreakHours: cleanStreakValue(todayStart: todayStart, calendar: calendar),
                        lastDetection: mostRecent.map(Date.init(timeIntervalSince1970:)))
    }

    /// Consecutive days with at least one recorded approach — the day-to-day "you showed up" run,
    /// ported from the Mac's `streakValue()`.
    ///
    /// One deliberate difference: a today that has recorded nothing *yet* does not break the run.
    /// The Mac starts counting at today and stops immediately, so a thirty-day streak reads as zero
    /// every morning and snaps back at the first touch — that measures the clock, not the habit.
    /// Here today only joins the run once it has something, and until then the run is read from
    /// yesterday.
    private func streakValue(todayStart: Date, calendar: Calendar) -> Int {
        var offset = (days[key(for: todayStart)]?.interruptions ?? 0) >= 1 ? 0 : 1
        var count = 0
        while offset < 366 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayStart),
                  let day = days[key(for: date)], day.interruptions >= 1 else { break }
            count += 1
            offset += 1
        }
        return count
    }

    /// Yesterday's longest run of consecutive hours with nothing recorded, measured only between
    /// its first and last approach — the quiet before the day started and after it ended is not an
    /// achievement.
    ///
    /// Yesterday rather than today, as on the Mac: today is unfinished, so its longest quiet run is
    /// really just "time since the last touch" and would climb all day on its own.
    private func cleanStreakValue(todayStart: Date, calendar: Calendar) -> Int? {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart),
              let day = days[key(for: yesterday)],
              // Under half an hour of tracking, a quiet stretch means the camera was off.
              day.activeSeconds >= 1800 else { return nil }
        let counts = day.hourlyInterruptions
        guard let firstActive = counts.firstIndex(where: { $0 > 0 }),
              let lastActive = counts.lastIndex(where: { $0 > 0 }),
              firstActive < lastActive else { return nil }

        var best = 0, current = 0
        for hour in firstActive...lastActive {
            if counts[hour] == 0 {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best > 0 ? best : nil
    }

    /// One day, hour by hour — what the heatmap draws. A day with nothing stored still returns 24
    /// empty hours, so the card keeps its shape from morning on.
    private static func hourBars(for day: Day, on start: Date) -> [DayBar] {
        let calendar = Calendar.current
        let pulls = day.pullsByHour
        let active = day.activeSecondsByHour
        return (0..<24).map { hour in
            let date = calendar.date(byAdding: .hour, value: hour, to: start) ?? start
            return DayBar(id: "h\(hour)", date: date,
                          interruptions: day.hourlyInterruptions.indices.contains(hour)
                                         ? day.hourlyInterruptions[hour] : 0,
                          prevented: 0,
                          pulls: pulls.indices.contains(hour) ? pulls[hour] : 0,
                          activeSeconds: active.indices.contains(hour) ? active[hour] : 0)
        }
    }

    /// Warm-up for a bucket spanning a whole day or more: one hour of tracked time. A young bucket
    /// otherwise divides by minutes and reads as thousands per hour.
    static let dayWarmUp = 3600.0

    /// Warm-up for a single hour-of-day bucket, which can never hold more than an hour of tracking.
    /// A full-hour floor would flatten those into raw counts, so they warm up in a quarter — the
    /// same pair of windows the Mac uses (`frontend/Sources/HourlyRate.swift`).
    static let hourWarmUp = 900.0

    static func hourlyRate(interruptions: Int, activeSeconds: Double,
                           warmUp: Double = dayWarmUp) -> Double {
        guard interruptions > 0, activeSeconds > 0 else { return 0 }
        return Double(interruptions) / (max(activeSeconds, warmUp) / 3600)
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
