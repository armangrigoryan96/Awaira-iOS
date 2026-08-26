import SwiftUI

/// "Goal progress": today's rate measured against the gentle target.
///
/// The comparison is stated three ways, so it lands whichever way the card is read — a sentence,
/// the two figures side by side, and a scale with the distance between them filled in. Warm means
/// over the target, accent means at or under it; the card never scolds, it only points.
struct GoalProgressCard: View {
    let goal: Double
    /// `nil` until there is enough tracked time to state a rate. The card then shows the target on
    /// its own rather than implying a reading of zero.
    let current: Double?

    var body: some View {
        let difference = (current ?? goal) - goal
        let overGoal = current != nil && difference > 0
        let tint = overGoal ? AwairaPalette.streak : AwairaPalette.accent

        return VStack(alignment: .leading, spacing: 0) {
            Text("GOAL PROGRESS")
                .font(.system(size: 11, weight: .medium))
                .kerning(0.6)
                .foregroundStyle(AwairaPalette.accent)

            Text("You noticed the pattern.")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AwairaPalette.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            summary(difference: difference, tint: tint)
                .padding(.top, 4)

            rule.padding(.top, 14)

            HStack(alignment: .center, spacing: 12) {
                column(label: "CURRENT",
                       value: current.map { String(format: "%.0f/hr", $0) } ?? "—",
                       size: 28,
                       // A tinted em-dash at 28pt reads as a coloured bar, not as "nothing measured
                       // yet" — the placeholder stays neutral until there is a rate.
                       tint: current == nil ? AwairaPalette.ink.opacity(0.3) : tint)
                Rectangle()
                    .fill(AwairaPalette.cardBorder)
                    .frame(width: 1, height: 48)
                column(label: "GOAL",
                       value: String(format: "Under %.0f/hr", goal),
                       size: 20,
                       tint: AwairaPalette.text)
            }
            .padding(.top, 12)

            GoalScaleTrack(goal: goal, current: current, tint: tint)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .awairaCard(padding: 14)
    }

    private var rule: some View {
        Rectangle()
            .fill(AwairaPalette.cardBorder)
            .frame(height: 1)
    }

    /// The sentence version of the comparison. The figure is coloured and the rest is not, so the
    /// distance is what the eye lands on.
    @ViewBuilder
    private func summary(difference: Double, tint: Color) -> some View {
        let body = Font.system(size: 15)
        let strong = Font.system(size: 15, weight: .semibold)

        Group {
            if current == nil {
                Text("Your rate appears once the camera has been on for a minute.")
                    .font(body)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.6))
            } else if abs(difference) < 0.5 {
                Text("You're right at your goal.")
                    .font(body)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.75))
            } else {
                let amount = String(format: "%.0f touches/hr", abs(difference))
                Text("You're ").font(body).foregroundStyle(AwairaPalette.ink.opacity(0.75))
                    + Text(amount).font(strong).foregroundStyle(tint)
                    + Text(difference > 0 ? " over your goal." : " under your goal.")
                        .font(body).foregroundStyle(AwairaPalette.ink.opacity(0.75))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// One column of the CURRENT / GOAL pair. Centred rather than left-aligned so the two read as
    /// a comparison across the divider instead of two unrelated stats.
    private func column(label: String, value: String, size: CGFloat, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .kerning(0.6)
                .foregroundStyle(AwairaPalette.ink.opacity(0.72))
            Text(value)
                .font(.system(size: size, design: .serif))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
