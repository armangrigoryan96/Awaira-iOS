import SwiftUI

/// "Today, hour by hour": one bar per waking hour, with the busy stretch of the day picked out in
/// amber and named.
///
/// The two readings answer different questions and the toggle is the honest way to offer both.
/// *Total touches* is where the day's volume went, and follows the shape of when the camera was on.
/// *Hourly rate* divides each hour's count by the time actually tracked in it, so an hour you only
/// watched for ten minutes is not flattered by the comparison.
struct HourBarChartView: View {
    /// One bar per hour, as `MobileStatsStore` builds them.
    let day: [MobileStatsStore.DayBar]
    let onOpenDetail: () -> Void

    private enum Mode: String, CaseIterable {
        case rate, total

        var title: String {
            switch self {
            case .rate:  return "Hourly rate"
            case .total: return "Total touches"
            }
        }
    }

    /// Volume first, as on the design's screen: it is the reading that needs no explaining.
    @State private var mode: Mode = .total

    private static let barGap: CGFloat = 3
    private static let plotHeight: CGFloat = 96
    private static let axisWidth: CGFloat = 20

    var body: some View {
        let hours = DayHourWindow.hours(in: day)
        let values = hours.map(value(of:))
        let peak = DayHourWindow.peak(in: hours, max: hours.map(\.interruptions).max() ?? 0)
        let scale = axisTop(for: values.max() ?? 0)

        VStack(alignment: .leading, spacing: 10) {
            titleRow
            picker

            if values.allSatisfy({ $0 <= 0 }) {
                emptyPlot
            } else {
                peakCaption(hours, peak: peak)
                plot(values: values, scale: scale, peak: peak)
                hourLabels(hours)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .awairaCard(padding: 12)
    }

    // MARK: - Chrome

    private var titleRow: some View {
        Button(action: onOpenDetail) {
            HStack(spacing: 6) {
                Text("TODAY, HOUR BY HOUR")
                    .font(.system(size: 11, weight: .medium))
                    .kerning(0.6)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AwairaPalette.ink.opacity(0.45))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("hourChartDetail")
    }

    /// A pair of pills rather than a `Picker(.segmented)`: the system control brings its own greys
    /// and corner radius, which read as a form field dropped onto a drawn card.
    private var picker: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases, id: \.self) { option in
                let isSelected = option == mode
                Button {
                    mode = option
                } label: {
                    Text(option.title)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? AwairaPalette.navSelectedText
                                                    : AwairaPalette.ink.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? AwairaPalette.navSelected : Color.clear,
                                    in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hourChartMode.\(option.rawValue)")
            }
        }
        .padding(2)
        .background(AwairaPalette.ink.opacity(0.06), in: Capsule())
        .animation(.easeInOut(duration: 0.15), value: mode)
    }

    // MARK: - Plot

    private func plot(values: [Double], scale: Double, peak: ClosedRange<Int>?) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            axis(scale: scale)

            ZStack(alignment: .bottom) {
                gridLines
                HStack(alignment: .bottom, spacing: Self.barGap) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        bar(value: value, scale: scale, isPeak: peak?.contains(index) ?? false)
                    }
                }
            }
            .frame(height: Self.plotHeight)
        }
    }

    private func bar(value: Double, scale: Double, isPeak: Bool) -> some View {
        // A bar for every hour, including the empty ones: the column spacing is what makes the
        // hour labels line up, and a chart that only drew the busy hours would slide its own
        // x-axis around as the day filled in.
        let fraction = scale > 0 ? min(1, value / scale) : 0
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 2,
                                   style: .continuous)
                .fill(value > 0 ? (isPeak ? AwairaPalette.rate : AwairaPalette.navSelected)
                                : AwairaPalette.ink.opacity(0.07))
                // Something tracked but tiny still deserves a mark, or a quiet hour and an
                // untracked one look identical.
                .frame(height: value > 0 ? max(2, Self.plotHeight * fraction) : 2)
        }
        .frame(maxWidth: .infinity)
    }

    private var gridLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                Rectangle()
                    .fill(AwairaPalette.cardBorder)
                    .frame(height: 1)
                if index < 2 { Spacer(minLength: 0) }
            }
        }
        .frame(height: Self.plotHeight)
    }

    private func axis(scale: Double) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            axisLabel(scale)
            Spacer(minLength: 0)
            axisLabel(scale / 2)
            Spacer(minLength: 0)
            axisLabel(0)
        }
        .frame(width: Self.axisWidth, height: Self.plotHeight, alignment: .trailing)
    }

    private func axisLabel(_ value: Double) -> some View {
        Text(value >= 10 || value == value.rounded() ? String(format: "%.0f", value)
                                                     : String(format: "%.1f", value))
            .font(.system(size: 9))
            .foregroundStyle(AwairaPalette.ink.opacity(0.5))
            .monospacedDigit()
            .lineLimit(1)
            // The label's own line box is taller than the rule it names; this pulls it back onto it.
            .alignmentGuide(.trailing) { $0[.trailing] }
    }

    /// Hour labels are sparse on purpose: at half the screen's width there is room for four or
    /// five before they collide, so they land on a stride that always includes both ends.
    private func hourLabels(_ hours: [MobileStatsStore.DayBar]) -> some View {
        let stride = max(1, Int((Double(hours.count) / 4).rounded()))
        return HStack(spacing: Self.barGap) {
            ForEach(Array(hours.enumerated()), id: \.offset) { index, bar in
                Text(index % stride == 0 ? Self.hourLabel(bar.date) : " ")
                    .font(.system(size: 9))
                    .foregroundStyle(AwairaPalette.ink.opacity(0.55))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.leading, Self.axisWidth + 6)
    }

    /// Named above the bars rather than bracketed below them: at this width a bracket's ticks were
    /// thinner than the gap between two bars, and the amber already says which bars it means.
    @ViewBuilder
    private func peakCaption(_ hours: [MobileStatsStore.DayBar], peak: ClosedRange<Int>?) -> some View {
        if let peak, let first = hours[safe: peak.lowerBound], let last = hours[safe: peak.upperBound] {
            Text("Peak window · \(Self.hourLabel(first.date))–\(Self.hourLabel(last.date))")
                .font(.system(size: 10))
                .foregroundStyle(AwairaPalette.rate)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        } else {
            // Held rather than dropped, so switching modes does not make the plot jump a line.
            Text(" ").font(.system(size: 10))
        }
    }

    private var emptyPlot: some View {
        Text("Nothing recorded yet today.")
            .font(.system(size: 12))
            .foregroundStyle(AwairaPalette.soft)
            .frame(maxWidth: .infinity, minHeight: Self.plotHeight + 24, alignment: .center)
    }

    // MARK: - Data

    private func value(of bar: MobileStatsStore.DayBar) -> Double {
        switch mode {
        case .total:
            return Double(bar.interruptions)
        case .rate:
            // The hour warm-up, not the day's: an hour bucket can never hold more than an hour of
            // tracking, and the full-hour floor would flatten this series back into raw counts.
            return MobileStatsStore.hourlyRate(interruptions: bar.interruptions,
                                               activeSeconds: bar.activeSeconds,
                                               warmUp: MobileStatsStore.hourWarmUp)
        }
    }

    /// A round number at or above the tallest bar, so the axis reads in steps a person would pick.
    private func axisTop(for maxValue: Double) -> Double {
        guard maxValue > 0 else { return 1 }
        let step: Double = maxValue <= 4 ? 1 : (maxValue <= 20 ? 5 : (maxValue <= 60 ? 10 : 20))
        return (maxValue / step).rounded(.up) * step
    }

    private static func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: date)
    }
}

private extension Array {
    /// The peak range is built from the same array it indexes, but reading it through an optional
    /// keeps a future caller from being able to crash the card with a stale range.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
