import SwiftUI

/// Local, evidence-led observations. The wording describes tracked activity rather than making
/// medical claims, and the presentation is intentionally a calm native list.
struct MobileInsightsView: View {
    @ObservedObject var detector: Detector

    private var patterns: [MobilePatternInsight] {
        MobilePatternInsight.make(week: detector.week,
                                  hourly: detector.hourOfWeek,
                                  weeklyRate: detector.weeklyRate,
                                  change: detector.weeklyImprovement)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 0) {
                        summaryValue("\(detector.weeklyTotal)", label: "7-day total")
                        Divider().frame(height: 42)
                        summaryValue(String(format: "%.1f", detector.weeklyRate), label: "per tracked hour")
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Your recent activity")
                } footer: {
                    Text("Stats are calculated from aggregate activity stored only on this iPhone.")
                }

                if patterns.isEmpty {
                    Section("Patterns worth noticing") {
                        ContentUnavailableView("Patterns will appear here",
                                               systemImage: "chart.xyaxis.line",
                                               description: Text("Use Awaira through a few sessions to see timing and day-to-day patterns."))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                } else {
                    Section("Patterns worth noticing") {
                        ForEach(patterns) { pattern in
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(pattern.title)
                                        .font(.body.weight(.semibold))
                                    Text(pattern.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } icon: {
                                Image(systemName: pattern.symbol)
                                    .foregroundStyle(pattern.tint)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section {
                    Text("These observations describe recent tracking, not your health or intent.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Insights")
        }
        .tint(.indigo)
    }

    private func summaryValue(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

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
            results.append(.init(id: "peak-hour", symbol: "clock", tint: .orange,
                                 title: "Your busiest window is \(hourRange(peak))",
                                 detail: "\(hourly[peak]) of \(total) moments (\(share)%) landed in this hour across the last seven days. Consider setting a cue just before it begins."))
        }

        if let busiest = week.max(by: { $0.interruptions < $1.interruptions }),
           busiest.interruptions >= 3,
           Double(busiest.interruptions) / Double(total) >= 0.28 {
            let share = Int((Double(busiest.interruptions) / Double(total) * 100).rounded())
            let day = busiest.date.formatted(.dateTime.weekday(.wide))
            results.append(.init(id: "peak-day", symbol: "calendar", tint: .purple,
                                 title: "\(day) stands out",
                                 detail: "\(share)% of your recent activity was logged that day. Consider what was different about your routine, workload, or setting."))
        }

        if let change, abs(change) >= 8 {
            let amount = Int(abs(change).rounded())
            let direction = change > 0 ? "lower" : "higher"
            results.append(.init(id: "rate-change", symbol: change > 0 ? "arrow.down.right" : "arrow.up.right",
                                 tint: change > 0 ? .green : .orange,
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
