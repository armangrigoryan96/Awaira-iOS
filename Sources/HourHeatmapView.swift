import SwiftUI

/// "Today, by hour": two rows of square cells — hand approaches on top, the ones that were
/// interrupted below — with a bracket under the busiest stretch of the day.
///
/// Ported from `awaira/frontend/Sources/HourHeatmapView.swift`; the geometry and the colour ramp are
/// the Mac's, narrowed for a phone (a shorter caption gutter, hour labels every second column).
///
/// A cool-to-warm ramp rather than one hue at varying opacity: quiet hours sit in deep blue and the
/// busiest come forward in amber, so the shape of the day is readable before any number is.
struct HourHeatmapView: View {
    /// One bar per hour, as `MobileStatsStore` builds them.
    let day: [MobileStatsStore.DayBar]

    /// The ramp, lifted from the design mockup.
    private static let stops: [Color] = [
        Color(hex: 0x154BB6), Color(hex: 0x006DF1), Color(hex: 0x007A79),
        Color(hex: 0x00A992), Color(hex: 0x8C9B36), Color(hex: 0xFEAF01),
    ]
    private static var peakTint: Color { stops[stops.count - 1] }

    /// Gap between neighbouring cells, and the width reserved for the two row captions.
    private static let gap: CGFloat = 4
    private static let captionWidth: CGFloat = 76

    var body: some View {
        let hours = DayHourWindow.hours(in: day)
        let maxCount = hours.map { max($0.interruptions, $0.pulls) }.max() ?? 0
        let peak = DayHourWindow.peak(in: hours, max: maxCount)

        VStack(alignment: .leading, spacing: 10) {
            Text("Today, by hour")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AwairaPalette.text)

            // Every row is one HStack sharing the same column geometry, and the cells size
            // themselves by aspect ratio rather than by a measured width. That keeps the captions on
            // the same baseline as their cells and lets the card end where the content ends.
            VStack(spacing: Self.gap) {
                gridRow { hourLabels(hours) }
                gridRow(caption: "Hand\napproaches") {
                    cells(hours, value: \.interruptions, max: maxCount)
                }
                gridRow(caption: "Interrupted") {
                    cells(hours, value: \.pulls, max: maxCount)
                }
                if let peak {
                    gridRow { peakBracket(hours, peak: peak) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .awairaCard()
    }

    /// One row of the grid: the caption gutter on the left, the hour columns on the right.
    private func gridRow<Content: View>(caption: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Group {
                if let caption {
                    Text(caption)
                        .font(.system(size: 12))
                        .foregroundStyle(AwairaPalette.ink.opacity(0.7))
                        .minimumScaleFactor(0.8)
                } else {
                    Color.clear.frame(height: 0)
                }
            }
            .frame(width: Self.captionWidth, alignment: .leading)

            content()
        }
    }

    private func hourLabels(_ hours: [MobileStatsStore.DayBar]) -> some View {
        // Every second hour on a phone: seventeen labels in that width collide.
        HStack(spacing: Self.gap) {
            ForEach(Array(hours.enumerated()), id: \.offset) { index, bar in
                Text(index % 2 == 0 ? Self.hourLabel(bar.date) : " ")
                    .font(.system(size: 9))
                    .foregroundStyle(AwairaPalette.ink.opacity(0.55))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func cells(_ hours: [MobileStatsStore.DayBar],
                       value: KeyPath<MobileStatsStore.DayBar, Int>,
                       max maxCount: Int) -> some View {
        HStack(spacing: Self.gap) {
            ForEach(Array(hours.enumerated()), id: \.offset) { _, bar in
                GeometryReader { geo in
                    // Measured off the mockup: a 47 px cell is inset by only ~4 px at the corner,
                    // i.e. a radius of about 9% of the side. Squares with the sharpness taken off,
                    // not rounded tiles.
                    RoundedRectangle(cornerRadius: Swift.max(2, geo.size.width * 0.09),
                                     style: .continuous)
                        .fill(Self.color(bar[keyPath: value], max: maxCount))
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// The peak *window*, not the peak hour: one cell under a label saying "window" was the wrong
    /// promise. The bracket opens upward — the rule runs along the bottom and the ticks rise to meet
    /// the cells.
    private func peakBracket(_ hours: [MobileStatsStore.DayBar], peak: ClosedRange<Int>) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: Self.gap) {
                ForEach(Array(hours.enumerated()), id: \.offset) { index, _ in
                    Group {
                        if peak.contains(index) {
                            BracketShape(open: index == peak.lowerBound,
                                         close: index == peak.upperBound)
                                .stroke(Self.peakTint, lineWidth: 1)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 6)

            // The caption needs more room than a narrow window gives it, so it is centred over the
            // bracket across the full row rather than clipped to the bracket's own columns, where it
            // came out as a stub ("eak windo").
            GeometryReader { geo in
                let step = geo.size.width / CGFloat(hours.count)
                let mid = (CGFloat(peak.lowerBound) + CGFloat(peak.upperBound) + 1) / 2 * step
                Text("Peak window")
                    .font(.system(size: 10))
                    .foregroundStyle(Self.peakTint)
                    .fixedSize()
                    .position(x: min(max(mid, 36), max(36, geo.size.width - 36)), y: 7)
            }
            .frame(height: 14)
        }
    }

    /// A bracket segment: the rule along the bottom, plus a tick rising at the open and/or close.
    private struct BracketShape: Shape {
        let open: Bool
        let close: Bool

        func path(in rect: CGRect) -> Path {
            var path = Path()
            if open {
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            }
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            if close {
                path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            }
            return path
        }
    }

    // MARK: - Data

    /// Position `count` on the ramp. Nothing at all stays a faint ghost cell rather than the ramp's
    /// coldest colour, so "quiet" and "not tracked" don't look alike.
    private static func color(_ count: Int, max maxCount: Int) -> Color {
        guard count > 0, maxCount > 0 else { return AwairaPalette.ink.opacity(0.07) }
        let t = min(1, Double(count) / Double(maxCount)) * Double(stops.count - 1)
        let index = Swift.min(Int(t), stops.count - 2)
        return stops[index].blended(with: stops[index + 1], fraction: t - Double(index))
    }

    private static func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: date)
    }
}
