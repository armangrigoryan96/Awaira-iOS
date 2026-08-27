import SwiftUI

/// "Touch locations": the head artwork with a count pinned over each zone that has been touched.
///
/// Ported from `awaira/frontend/Sources/TouchZonesCard.swift`, artwork and anchors included.
/// `counts` is whichever day the week strip has selected — Today hands it `zonesByDay`, the same
/// way it feeds the heatmap, so the head and the hours below it always describe the same day.
/// (The Mac's `zoneBreakdown` is today-only; the phone's strip is the selection, so it follows it.)
/// Until the first classified touch of that day it is empty and the card shows its empty line.
struct TouchZonesCard: View {
    /// Per-zone totals for the shown day, keyed the way the classifier names a zone ("cheek-right").
    var counts: [String: Int] = [:]
    @Binding var mirrored: Bool
    @State private var showingInfo = false

    init(counts: [String: Int] = [:], mirrored: Binding<Bool> = .constant(false)) {
        self.counts = counts
        self._mirrored = mirrored
    }

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
            MobileCardHeader(title: "Touch locations") {
                Button {
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .scaledFont(25, weight: .medium)
                        .foregroundStyle(AwairaPalette.ink.opacity(0.72))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About touch locations")
            }

            HStack(alignment: .center, spacing: 14) {
                head
                VStack(alignment: .leading, spacing: 12) {
                    legend
                    if counts.isEmpty {
                        MobileEmptyNote(text: "No touches recorded yet.")
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .awairaCard(padding: 18)
        .alert("Touch locations", isPresented: $showingInfo) {
            Button("Done", role: .cancel) { }
        } message: {
            Text("The numbered markers show the locations noticed by your on-device detector. The colors indicate their relative frequency for the selected day.")
        }
    }

    private var head: some View {
        let maxCount = counts.values.max() ?? 0
        return Image("head")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            // A definite cap, not `.infinity`: inside a scroll view the height proposal is
            // unbounded, and a head that grows into it would push the card past the fold.
            .frame(width: 185, height: 270)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .overlay {
                // Every zone that has been touched gets its pill, always in the same place. Ranking
                // them and dropping collisions meant a number could vanish, or seem to jump to
                // another part of the face, because some *other* zone had grown.
                GeometryReader { geo in
                    ForEach(Self.anchors, id: \.zone) { anchor in
                        if let count = counts[anchor.zone], count > 0 {
                            pill(count, max: maxCount)
                                .position(x: geo.size.width * (mirrored ? 1 - anchor.x : anchor.x),
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
            .scaledFont(11, weight: .semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint, in: Capsule())
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            legendRow(Self.high, "High", value: bucketTotals.high)
            legendRow(Self.medium, "Medium", value: bucketTotals.medium)
            legendRow(Self.low, "Low", value: bucketTotals.low)
        }
    }

    private func legendRow(_ color: Color, _ label: String, value: Int) -> some View {
        HStack(spacing: 9) {
            Circle().fill(color).frame(width: 11, height: 11)
            Text(label)
                .awairaCaption(16)
                .foregroundStyle(AwairaPalette.ink.opacity(0.75))
            Spacer(minLength: 4)
            Text("\(value)")
                .awairaStat(16)
                .foregroundStyle(AwairaPalette.ink.opacity(0.75))
        }
    }

    private var bucketTotals: (high: Int, medium: Int, low: Int) {
        let maximum = counts.values.max() ?? 0
        guard maximum > 0 else { return (0, 0, 0) }
        return counts.values.reduce(into: (high: 0, medium: 0, low: 0)) { result, count in
            let share = Double(count) / Double(maximum)
            if share >= 0.66 { result.high += count }
            else if share >= 0.33 { result.medium += count }
            else { result.low += count }
        }
    }

    private var topZonesText: String {
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return "" }
        let leaders = counts.sorted { $0.value > $1.value }.prefix(2).map { zone, count in
            "\(Self.displayName(zone)) (\(Int((Double(count) / Double(total) * 100).rounded()))%)"
        }
        return leaders.isEmpty ? "" : "Most touched: " + leaders.joined(separator: " and ") + "."
    }

    private static func displayName(_ zone: String) -> String {
        zone.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "left", with: "")
            .replacingOccurrences(of: "right", with: "")
            .trimmingCharacters(in: .whitespaces)
            .capitalized
    }
}
