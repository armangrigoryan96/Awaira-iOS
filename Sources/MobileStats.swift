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
        var lastDetection: TimeInterval?
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
        let week: [DayBar]
        let hourOfWeek: [Int]
        let weeklyTotal: Int
        let weeklyRate: Double
        /// Positive means the current seven-day rate is lower than the preceding seven days.
        let weeklyImprovement: Double?
        let lastDetection: Date?
    }

    private static let storageKey = "awaira.mobile.stats.v1"
    private var days: [String: Day]
    private var lastSave = Date.distantPast

    init(defaults: UserDefaults = .standard) {
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
            if sustained { $0.pulls += 1 }
            else { $0.prevented += 1 }
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
        return Snapshot(today: today, week: week, hourOfWeek: hourly, weeklyTotal: weeklyTotal,
                        weeklyRate: weeklyRate, weeklyImprovement: improvement,
                        lastDetection: mostRecent.map(Date.init(timeIntervalSince1970:)))
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
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func pruneHistory() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -370, to: Date()) ?? .distantPast
        let cutoffKey = key(for: cutoff)
        days = days.filter { $0.key >= cutoffKey }
    }
}
