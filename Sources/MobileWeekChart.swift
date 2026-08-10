import SwiftUI

/// Compact seven-day chart used by the iPhone dashboard. It intentionally presents aggregate
/// counts only; no camera image or per-event location is part of the visualisation.
///
/// The bars show either the raw daily total or the per-hour rate, chosen by the dashboard's
/// Total / Hourly switch — the same two views the desktop app offers.
struct MobileWeekChart: View {
    let days: [MobileStatsStore.DayBar]
    var mode: WeekChartMode = .total

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter
    }()

    /// The value a given day contributes in the current mode.
    private func value(_ day: MobileStatsStore.DayBar) -> Double {
        switch mode {
        case .total:  return Double(day.interruptions)
        case .hourly: return MobileStatsStore.hourlyRate(interruptions: day.interruptions,
                                                          activeSeconds: day.activeSeconds)
        }
    }

    private func label(_ value: Double) -> String {
        guard value > 0 else { return "" }
        switch mode {
        case .total:  return "\(Int(value.rounded()))"
        case .hourly: return String(format: "%.1f", value)
        }
    }

    var body: some View {
        let maximum = max(days.map(value).max() ?? 0, mode == .total ? 1 : 0.1)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(days) { day in
                let v = value(day)
                VStack(spacing: 6) {
                    Text(label(v))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .frame(height: 12)
                    Capsule()
                        .fill(day.id == days.last?.id ? Color.mint : Color.white.opacity(0.28))
                        .frame(height: max(5, 76 * CGFloat(v) / CGFloat(maximum)))
                        .frame(maxHeight: 76, alignment: .bottom)
                    Text(Self.dayFormatter.string(from: day.date))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.52))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seven-day interruption chart")
    }
}

/// Whether the week chart shows raw daily totals or the per-hour rate.
enum WeekChartMode: String, CaseIterable, Identifiable {
    case total, hourly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .total:  return "Total"
        case .hourly: return "Hourly"
        }
    }
}
