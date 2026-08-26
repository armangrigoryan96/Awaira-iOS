import SwiftUI

/// "Touch locations": the head artwork with a count pinned over each zone that has been touched.
///
/// Ported from `awaira/frontend/Sources/TouchZonesCard.swift`, artwork and anchors included.
/// `counts` is today's tally from `Detector.zoneCounts` — today only, like the Mac's
/// `zoneBreakdown`, so the head does not follow the week strip the way the heatmap does. Until the
/// first classified touch of the day it is empty and the card shows its empty line.
///
/// At half the page's width there is no room beside the head, so the High/Medium/Low legend lives
/// on the detail screen and the card states its finding in words instead: the colours are a ranking
/// of one day's zones, and the two that lead it are the thing worth reading.
struct TouchZonesCard: View {
    /// Per-zone totals for today, keyed the way the classifier names a zone ("cheek-right").
    var counts: [String: Int] = [:]
    let onOpenDetail: () -> Void

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

    /// How each zone is named in a sentence. Every key in `anchors` needs one, or the summary line
    /// would fall back to the classifier's own hyphenated id.
    static let displayNames: [String: String] = [
        "topofhead":    "Top of head",
        "hair-left":    "Left hair",
        "hair-right":   "Right hair",
        "forehead":     "Forehead",
        "temple-left":  "Left temple",
        "temple-right": "Right temple",
        "eye-left":     "Left eye",
        "eye-right":    "Right eye",
        "ear-left":     "Left ear",
        "ear-right":    "Right ear",
        "nose":         "Nose",
        "cheek-left":   "Left cheek",
        "cheek-right":  "Right cheek",
        "mouth":        "Mouth",
        "chin":         "Chin",
        "neck":         "Neck",
    ]

    /// The legend's three colours, in the order the legend lists them. Shared with the detail
    /// screen, which is where the legend itself now lives.
    static let high = Color(hex: 0xFC8434)
    static let medium = Color(hex: 0x16C795)
    static let low = Color(hex: 0x0059E9)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleRow
            head
                .frame(maxWidth: .infinity)
            summary
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .awairaCard(padding: 12)
    }

    private var titleRow: some View {
        Button(action: onOpenDetail) {
            HStack(spacing: 6) {
                Text("TOUCH LOCATIONS")
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
        .accessibilityIdentifier("zonesDetail")
    }

    private var head: some View {
        let maxCount = counts.values.max() ?? 0
        return Image("head")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            // A definite cap, not `.infinity`: inside a scroll view the height proposal is
            // unbounded, and a head that grows into it would push the card past the fold.
            .frame(maxWidth: 150, minHeight: 96, maxHeight: 170)
            .overlay {
                // Every zone that has been touched gets its pill, always in the same place. Ranking
                // them and dropping collisions meant a number could vanish, or seem to jump to
                // another part of the face, because some *other* zone had grown.
                GeometryReader { geo in
                    ForEach(Self.anchors, id: \.zone) { anchor in
                        if let count = counts[anchor.zone], count > 0 {
                            pill(count, max: maxCount)
                                .position(x: geo.size.width * anchor.x,
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
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint, in: Capsule())
    }

    /// The card's finding in one sentence. Percentages are shares of the day's *classified* touches,
    /// which is legitimately fewer than the day's approaches — a touch the classifier could not name
    /// is counted by neither the head nor this line.
    @ViewBuilder
    private var summary: some View {
        let ranked = Self.ranked(counts)
        let total = counts.values.reduce(0, +)

        if ranked.isEmpty || total == 0 {
            Text("No touches recorded yet today.")
                .font(.system(size: 12))
                .foregroundStyle(AwairaPalette.soft)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            let body = Font.system(size: 12)
            let strong = Font.system(size: 12, weight: .semibold)
            let leading = Text("Most touched: ").font(body).foregroundStyle(AwairaPalette.ink.opacity(0.7))

            (ranked.dropFirst().first.map { second in
                leading
                    + Self.phrase(ranked[0], total: total, body: body, strong: strong)
                    + Text(" and ").font(body).foregroundStyle(AwairaPalette.ink.opacity(0.7))
                    + Self.phrase(second, total: total, body: body, strong: strong)
                    + Text(".").font(body).foregroundStyle(AwairaPalette.ink.opacity(0.7))
            } ?? (leading
                    + Self.phrase(ranked[0], total: total, body: body, strong: strong)
                    + Text(".").font(body).foregroundStyle(AwairaPalette.ink.opacity(0.7))))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func phrase(_ entry: (zone: String, count: Int), total: Int,
                               body: Font, strong: Font) -> Text {
        let share = Int((Double(entry.count) / Double(total) * 100).rounded())
        return Text(displayNames[entry.zone] ?? entry.zone)
                .font(strong).foregroundStyle(AwairaPalette.text)
            + Text(" (\(share)%)").font(body).foregroundStyle(AwairaPalette.ink.opacity(0.7))
    }

    /// Zones by count, busiest first. Ties break on the zone name so the sentence does not reword
    /// itself between two equal zones on every refresh.
    static func ranked(_ counts: [String: Int]) -> [(zone: String, count: Int)] {
        counts.filter { $0.value > 0 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { (zone: $0.key, count: $0.value) }
    }
}
