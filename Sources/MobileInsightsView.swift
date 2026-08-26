import SwiftUI

/// Local, evidence-led observations drawn from the stored aggregates. The wording describes tracked
/// activity rather than making medical claims — it says what the numbers did, never what it means
/// about the person.
///
/// The list that used to render these lives on in `MobilePatternsView`, repainted in the Awaira
/// palette; only the generator belongs here.
struct MobilePatternInsight: Identifiable {
    let id: String
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    static func make(week: [MobileStatsStore.DayBar], hourly: [Int], weeklyRate: Double,
                     change: Double?) -> [MobilePatternInsight] {
        let total = week.reduce(0) { $0 + $1.interruptions }
        guard total >= 6 else { return [] }
        var results: [MobilePatternInsight] = []

        if let peak = hourly.indices.max(by: { hourly[$0] < hourly[$1] }), hourly[peak] >= 3 {
            let share = Int((Double(hourly[peak]) / Double(total) * 100).rounded())
            results.append(.init(id: "peak-hour", symbol: "clock", tint: AwairaPalette.rate,
                                 title: "Your busiest window is \(hourRange(peak))",
                                 detail: "\(hourly[peak]) of \(total) moments (\(share)%) landed in this hour across the last seven days. Consider setting a cue just before it begins."))
        }

        if let busiest = week.max(by: { $0.interruptions < $1.interruptions }),
           busiest.interruptions >= 3,
           Double(busiest.interruptions) / Double(total) >= 0.28 {
            let share = Int((Double(busiest.interruptions) / Double(total) * 100).rounded())
            let day = busiest.date.formatted(.dateTime.weekday(.wide))
            results.append(.init(id: "peak-day", symbol: "calendar", tint: AwairaPalette.navSelected,
                                 title: "\(day) stands out",
                                 detail: "\(share)% of your recent activity was logged that day. Consider what was different about your routine, workload, or setting."))
        }

        if let change, abs(change) >= 8 {
            let amount = Int(abs(change).rounded())
            let direction = change > 0 ? "lower" : "higher"
            results.append(.init(id: "rate-change", symbol: change > 0 ? "arrow.down.right" : "arrow.up.right",
                                 tint: change > 0 ? AwairaPalette.accent : AwairaPalette.streak,
                                 title: "Your rate is \(amount)% \(direction) than last week",
                                 detail: String(format: "This compares interruptions per tracked hour (%.1f per hour this week).", weeklyRate)))
        }

        return Array(results.prefix(3))
    }

    private static func hourRange(_ hour: Int) -> String {
        func text(_ value: Int) -> String {
            let h = value % 12 == 0 ? 12 : value % 12
            return "\(h) \(value < 12 ? "AM" : "PM")"
        }
        return "\(text(hour))–\(text((hour + 1) % 24))"
    }
}
