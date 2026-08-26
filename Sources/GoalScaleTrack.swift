import SwiftUI

/// The goal card's comparison scale: one track carrying the gentle target and today's rate, with
/// the stretch between them filled in. The fill *is* the message — its length is the distance left
/// to close (or the room to spare), which a bar growing from zero cannot show.
///
/// Ported from `awaira/frontend/Sources/GoalScaleTrack.swift`, geometry unchanged. The Mac's
/// `L(...)` calls become literals (the phone has no localisation layer) and its `\.fontScale`
/// environment value becomes a fixed 11pt, since nothing on iOS reads that scale.
struct GoalScaleTrack: View {
    let goal: Double
    /// `nil` until there is enough tracked time to state a rate; the track then shows the target
    /// alone rather than implying a reading of zero.
    let current: Double?
    let tint: Color

    /// Headroom past the larger of the two values, so neither marker ends up pinned to the end of
    /// the track with nothing beyond it.
    private var scaleMax: Double { max(1, max(goal, current ?? goal) * 1.15) }

    private let labelSize: CGFloat = 11
    private var topBand: CGFloat { labelSize + 5 }
    private var bottomBand: CGFloat { labelSize + 5 }
    private let connector: CGFloat = 7
    private let trackHeight: CGFloat = 12

    var body: some View {
        let trackTop = topBand + connector
        let centerY = trackTop + trackHeight / 2
        let labelHalf = max(26, labelSize * 2.4)

        return GeometryReader { geo in
            let width = geo.size.width
            let goalX = position(goal, in: width)
            let currentX = current.map { position($0, in: width) }
            let labels = labelPositions(goalX: goalX, currentX: currentX, width: width, half: labelHalf)
            // A rate sitting on its target would otherwise print the same figure twice, side by
            // side, which reads as a rendering fault rather than as a match. One marker, one value.
            let coincident = current.map { abs($0 - goal) < 0.5 } ?? false

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(AwairaPalette.ink.opacity(0.10))
                    .frame(width: width, height: trackHeight)
                    .position(x: width / 2, y: centerY)

                if let currentX {
                    let lo = min(goalX, currentX)
                    let hi = max(goalX, currentX)
                    // No minimum width: a rate sitting exactly on its target should show no fill
                    // at all, and rounding one up would spill the cap past the marker it starts at.
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, hi - lo), height: trackHeight)
                        .position(x: (lo + hi) / 2, y: centerY)
                }

                marker(x: goalX,
                       valueX: labels.goal,
                       wordX: labels.goal,
                       color: AwairaPalette.accent,
                       dashed: false,
                       value: coincident ? nil : String(format: "%.0f/hr", goal),
                       word: "Goal",
                       centerY: centerY)

                if let currentX, let currentValue = current {
                    marker(x: currentX,
                           // With one shared marker the single figure belongs over it, not over
                           // the word that had to be nudged aside to make room for its pair.
                           valueX: coincident ? clamped(currentX, in: width, half: labelHalf)
                                              : (labels.current ?? currentX),
                           wordX: labels.current ?? currentX,
                           color: tint,
                           dashed: true,
                           value: String(format: "%.0f/hr", currentValue),
                           word: "Current",
                           centerY: centerY)
                }
            }
        }
        .frame(height: topBand + connector + trackHeight + connector + bottomBand)
    }

    /// A marker is four pieces at one x: a leader line through the track, the dot itself, the
    /// value above and the word below. Dashed for the live rate, solid for the fixed target.
    @ViewBuilder
    private func marker(x: CGFloat, valueX: CGFloat, wordX: CGFloat, color: Color, dashed: Bool,
                        value: String?, word: String, centerY: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: x, y: topBand))
            path.addLine(to: CGPoint(x: x, y: topBand + connector + trackHeight + connector))
        }
        .stroke(color.opacity(0.75),
                style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 3] : []))

        Circle()
            .fill(AwairaPalette.statsSurface)
            .frame(width: trackHeight + 4, height: trackHeight + 4)
            .overlay(Circle().strokeBorder(color, lineWidth: 3))
            .position(x: x, y: centerY)

        if let value {
            Text(value)
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(color)
                .fixedSize()
                .position(x: valueX, y: labelSize / 2 + 1)
        }

        Text(word)
            .font(.system(size: labelSize, weight: .medium))
            .foregroundStyle(color.opacity(0.85))
            .fixedSize()
            .position(x: wordX,
                      y: topBand + connector + trackHeight + connector + labelSize / 2 + 2)
    }

    private func position(_ value: Double, in width: CGFloat) -> CGFloat {
        let inset = trackHeight / 2 + 2
        let usable = max(1, width - inset * 2)
        let fraction = min(1, max(0, value / scaleMax))
        return inset + usable * CGFloat(fraction)
    }

    /// Labels stay inside the card and off each other: each is pulled back from the edges, and a
    /// pair that would collide (a rate sitting on its target) is spread either side of the two
    /// markers' midpoint. The leader lines stay put, so a nudged label still reads as its own.
    private func labelPositions(goalX: CGFloat, currentX: CGFloat?, width: CGFloat,
                                half: CGFloat) -> (goal: CGFloat, current: CGFloat?) {
        guard let currentX else { return (clamped(goalX, in: width, half: half), nil) }
        let goalLabel = clamped(goalX, in: width, half: half)
        let currentLabel = clamped(currentX, in: width, half: half)
        guard abs(currentLabel - goalLabel) < half * 2 else { return (goalLabel, currentLabel) }

        // Spread the pair around their midpoint, then slide the *pair* back inside the card if
        // that pushed one past an edge. Clamping them individually would undo the spread and butt
        // the two words together again — which is what a target near the end of the scale did.
        let low = half
        let high = max(half, width - half)
        var left = (goalLabel + currentLabel) / 2 - half
        var right = left + half * 2
        if right > high { right = high; left = right - half * 2 }
        if left < low { left = low; right = left + half * 2 }

        let goalFirst = goalX <= currentX
        return (clamped(goalFirst ? left : right, in: width, half: half),
                clamped(goalFirst ? right : left, in: width, half: half))
    }

    /// Keeps a label's centre far enough from both edges that its full width stays on the card.
    private func clamped(_ x: CGFloat, in width: CGFloat, half: CGFloat) -> CGFloat {
        min(max(x, half), max(half, width - half))
    }
}
