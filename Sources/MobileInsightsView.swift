import SwiftUI

/// Evidence-led observations from the local seven-day history. These are deliberately framed as
/// patterns, never diagnoses or promises: an empty hour can simply mean the app was not tracking.
struct MobileInsightsView: View {
    @ObservedObject var detector: Detector

    var body: some View {
        ScrollView(showsIndicators: false) {
            MobileInsightsSection(detector: detector)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 28)
        }
        .foregroundStyle(.white)
    }
}

/// Reused at the bottom of the dashboard so patterns follow the supporting chart and settings,
/// without asking people to switch tabs for the most useful part of their progress data.
struct MobileInsightsSection: View {
    @ObservedObject var detector: Detector

    private var patterns: [MobilePatternInsight] {
        MobilePatternInsight.make(week: detector.week,
                                  hourly: detector.hourOfWeek,
                                  weeklyRate: detector.weeklyRate,
                                  change: detector.weeklyImprovement)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Insights")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                    Text("Patterns from your recent on-device history")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.62))
                }

                rateSummary

                if patterns.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Patterns worth noticing")
                            .font(.headline)
                        ForEach(patterns) { pattern in
                            patternCard(pattern)
                        }
                    }
                }

                Text("Awaira only uses the aggregate activity stored on this iPhone. These observations describe your recent tracking, not your health or intent.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
        }
    }

    private var rateSummary: some View {
        HStack(spacing: 12) {
            summaryValue("\(detector.weeklyTotal)", label: "7-day total")
            summaryValue(String(format: "%.1f", detector.weeklyRate), label: "per tracked hour")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.mint.opacity(0.24), lineWidth: 1) }
    }

    private func summaryValue(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundStyle(.mint)
            Text("Your patterns will appear here")
                .font(.headline)
            Text("Use Awaira through a few sessions. Once there is enough activity, you’ll see timing and day-to-day patterns—not just a counter.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func patternCard(_ pattern: MobilePatternInsight) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: pattern.symbol)
                .font(.headline)
                .foregroundStyle(pattern.tint)
                .frame(width: 36, height: 36)
                .background(pattern.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(pattern.title).font(.subheadline.weight(.semibold))
                Text(pattern.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.63))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1) }
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

        if let peak = hourly.indices.max(by: { hourly[$0] < hourly[$1] }),
           hourly[peak] >= 3 {
            let share = Int((Double(hourly[peak]) / Double(total) * 100).rounded())
            results.append(.init(id: "peak-hour", symbol: "clock.fill", tint: .orange,
                                 title: "Your busiest window is \(hourRange(peak))",
                                 detail: "\(hourly[peak]) of \(total) moments (\(share)%) landed in this hour across the last seven days. Try setting up a cue just before it begins."))
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
                                 tint: change > 0 ? .mint : .yellow,
                                 title: "Your rate is \(amount)% \(direction) than last week",
                                 detail: String(format: "This compares interruptions per tracked hour, so it accounts for how long Awaira was active (%.1f per hour this week).", weeklyRate)))
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
