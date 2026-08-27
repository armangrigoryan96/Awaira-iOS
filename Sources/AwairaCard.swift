import SwiftUI
import UIKit

// Shared chrome for the dashboard, ported from `awaira/frontend/Sources/AwairaCard.swift`: one card
// treatment, one pill treatment, and the two colour helpers the heatmap and the zone pills need.
// Kept together so a card can never drift into having its own radius or border opacity.

extension View {
    /// The design's card: a hairline outline over a graphite fill.
    ///
    /// `fill: true` lets the card grow to the height of whatever it is sharing a row with. It has
    /// to be applied here, before the background, or the border would stay wrapped around the
    /// content while the row around it got taller. See `awairaRow`.
    func awairaCard(padding: CGFloat = 14, fill: Bool = false) -> some View {
        awairaCardBody(padding: padding, fill: fill, stroke: AwairaPalette.cardBorder)
    }

    /// A card outlined in a solid accent line instead of the neutral hairline — for the one card on
    /// a page that is the page's own conclusion.
    func awairaAccentCard(padding: CGFloat = 14, fill: Bool = false) -> some View {
        awairaCardBody(padding: padding, fill: fill, stroke: AwairaPalette.accent.opacity(0.55))
    }

    private func awairaCardBody(padding: CGFloat, fill: Bool, stroke: Color) -> some View {
        self
            .padding(padding)
            .frame(maxHeight: fill ? .infinity : nil, alignment: .topLeading)
            .background(AwairaPalette.statsSurface,
                        in: RoundedRectangle(cornerRadius: AwairaPalette.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AwairaPalette.cardRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
    }

    /// A row of cards that all end at the same baseline, as the design draws them.
    ///
    /// `fixedSize(vertical:)` makes the row adopt its own ideal height — the tallest card's — and
    /// only then hand that height down, so the `fill: true` cards inside stretch to meet it. Without
    /// it the row sits inside a scroll view with no height to offer and every card keeps its own.
    func awairaRow() -> some View {
        fixedSize(horizontal: false, vertical: true)
    }

    /// Header pill: a true half-round capsule filled with the page's own colour, separated from it
    /// by nothing but the card hairline.
    func awairaPill(horizontal: CGFloat = 12, vertical: CGFloat = 7) -> some View {
        self
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(AwairaPalette.window, in: Capsule())
            .overlay(Capsule().strokeBorder(AwairaPalette.cardBorder, lineWidth: 1))
    }
}

/// A vertical hairline, for splitting a card into two figures side by side. Matches the Mac's
/// `stripDivider`.
struct AwairaVerticalRule: View {
    var height: CGFloat = 46

    var body: some View {
        Rectangle()
            .fill(AwairaPalette.cardBorder)
            .frame(width: 1, height: height)
    }
}

extension Color {
    /// Build from a packed 0xRRGGBB literal — the form the design values are quoted in.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// Linear mix towards `other`, for positioning a value on a colour ramp.
    func blended(with other: Color, fraction: Double) -> Color {
        let t = min(1, max(0, fraction))
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        guard UIColor(self).getRed(&ar, green: &ag, blue: &ab, alpha: &aa),
              UIColor(other).getRed(&br, green: &bg, blue: &bb, alpha: &ba) else { return self }
        return Color(.sRGB,
                     red:   ar + (br - ar) * t,
                     green: ag + (bg - ag) * t,
                     blue:  ab + (bb - ab) * t,
                     opacity: 1)
    }
}
