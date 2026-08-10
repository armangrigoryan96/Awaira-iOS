import SwiftUI

/// Compact seven-day chart used by the iPhone dashboard. It intentionally presents aggregate
/// counts only; no camera image or per-event location is part of the visualisation.
struct MobileWeekChart: View {
    let days: [MobileStatsStore.DayBar]

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter
    }()

    var body: some View {
        let maximum = max(days.map(\.interruptions).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    Text(day.interruptions == 0 ? "" : "\(day.interruptions)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .frame(height: 12)
                    Capsule()
                        .fill(day.id == days.last?.id ? Color.mint : Color.white.opacity(0.28))
                        .frame(height: max(5, 76 * CGFloat(day.interruptions) / CGFloat(maximum)))
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
