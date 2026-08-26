import SwiftUI

/// "Touch locations": the head artwork with a count pinned over each zone that has been touched.
///
/// Ported from `awaira/frontend/Sources/TouchZonesCard.swift`, artwork and anchors included.
/// `counts` is today's tally from `Detector.zoneCounts` — today only, like the Mac's
/// `zoneBreakdown`, so the head does not follow the week strip the way the heatmap does. Until the
/// first classified touch of the day it is empty and the card shows its empty line.
struct TouchZonesCard: View {
    /// Presentation only: changing the map's orientation does not alter stored zone names.
    @AppStorage("touchZonesMirrored") private var mirrored = true

    /// Per-zone totals for today, keyed the way the classifier names a zone ("cheek-right").
    var counts: [String: Int] = [:]

    /// Where each zone's pill sits, in fractions of the head artwork (0,0 = its top-left corner).
    /// Measured off the artwork against a 5% grid, not estimated; re-measure if it is ever
    /// re-cropped, because the crop follows the silhouette.
    ///
    /// "left"/"right" name the side the *person* touched, so the artwork reads like a mirror: your
    /// right cheek lights up the right of the picture.
    ///
    /// This is every name the classifier can produce, all sixteen. Nothing here may be left out: a
    /// zone with no anchor is silently invisible however often it is touched.
    private static let anchors: [(zone: String, x: CGFloat, y: CGFloat)] = [
        ("topofhead",    0.50, 0.040),
        ("hair-left",    0.36, 0.140),
        ("hair-right",   0.64, 0.140),
        ("forehead",     0.50, 0.250),
        ("temple-left",  0.21, 0.285),
        ("temple-right", 0.79, 0.285),
        ("eye-left",     0.35, 0.375),
        ("eye-right",    0.65, 0.375),
        ("ear-left",     0.09, 0.420),
        ("ear-right",    0.91, 0.420),
        ("nose",         0.50, 0.460),
        ("cheek-left",   0.20, 0.550),
        ("cheek-right",  0.80, 0.550),
        ("mouth",        0.50, 0.565),
        ("chin",         0.50, 0.670),
        ("neck",         0.50, 0.780),
    ]

    /// The legend's three colours, in the order the legend lists them.
    private static let high = Color(hex: 0xFC8434)
    private static let medium = Color(hex: 0x16C795)
    private static let low = Color(hex: 0x0059E9)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Touch locations")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AwairaPalette.text)

                Spacer(minLength: 0)

                Toggle("Mirror", isOn: $mirrored)
                    .font(.system(size: 12, weight: .medium))
                    .accessibilityHint("Show left and right sides as they appear in a mirror.")
            }

            HStack(alignment: .center, spacing: 16) {
                head
                VStack(alignment: .leading, spacing: 12) {
                    legend
                    if counts.isEmpty {
                        Text("No touches recorded yet today.")
                            .font(.system(size: 12))
                            .foregroundStyle(AwairaPalette.soft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .awairaCard(padding: 14)
    }

    private var head: some View {
        let maxCount = counts.values.max() ?? 0
        return Image("head")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            // A definite cap, not `.infinity`: inside a scroll view the height proposal is
            // unbounded, and a head that grows into it would push the card past the fold.
            .frame(maxWidth: 160, minHeight: 96, maxHeight: 200)
            .overlay {
                // Every zone that has been touched gets its pill, always in the same place. Ranking
                // them and dropping collisions meant a number could vanish, or seem to jump to
                // another part of the face, because some *other* zone had grown.
                GeometryReader { geo in
                    ForEach(Self.anchors, id: \.zone) { anchor in
                        if let count = counts[anchor.zone], count > 0 {
                            pill(count, max: maxCount)
                                .position(x: geo.size.width * displayX(for: anchor),
                                          y: geo.size.height * anchor.y)
                        }
                    }
                }
            }
    }

    private func pill(_ count: Int, max maxCount: Int) -> some View {
        let share = maxCount > 0 ? Double(count) / Double(maxCount) : 0
        let tint = share >= 0.66 ? Self.high : (share >= 0.33 ? Self.medium : Self.low)
        return Text("\(count)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint, in: Capsule())
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            legendRow(Self.high, "High")
            legendRow(Self.medium, "Medium")
            legendRow(Self.low, "Low")
        }
    }

    private func legendRow(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 9) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(AwairaPalette.ink.opacity(0.75))
        }
    }

    /// The original map is mirrored; the alternative swaps the visual left/right positions.
    private func displayX(for anchor: (zone: String, x: CGFloat, y: CGFloat)) -> CGFloat {
        mirrored ? anchor.x : 1 - anchor.x
    }
}
