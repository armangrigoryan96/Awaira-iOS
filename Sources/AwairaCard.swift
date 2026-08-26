import SwiftUI
import UIKit

// Shared chrome for the dashboard, ported from `awaira/frontend/Sources/AwairaCard.swift`: one card
// treatment, one pill treatment, and the two colour helpers the heatmap and the zone pills need.
// Kept together so a card can never drift into having its own radius or border opacity.

extension View {
    /// The design's card: a hairline outline over the page's own fill. In dark the fill *is* the
    /// page colour, so this reads as a drawn region rather than a raised panel.
    func awairaCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(AwairaPalette.statsSurface,
                        in: RoundedRectangle(cornerRadius: AwairaPalette.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AwairaPalette.cardRadius, style: .continuous)
                    .strokeBorder(AwairaPalette.cardBorder, lineWidth: 1)
            )
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
