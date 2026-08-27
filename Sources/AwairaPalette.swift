import SwiftUI
import UIKit

/// The Mac dashboard's palette, ported to iOS. Every value is copied from
/// `awaira/frontend/Sources/AwairaPalette.swift` — the two apps draw the same design, so a colour
/// only ever changes in both places at once.
///
/// `NSColor(name:)` becomes `UIColor(dynamicProvider:)`: same idea, one colour that resolves
/// differently in light and dark, so following the system theme repaints every surface at once.
enum AwairaPalette {
    private static func dynamic(dark: UIColor, light: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> UIColor {
        UIColor(red: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: 1)
    }

    /// The single "content" colour: near-white on dark, near-black slate on light. Text and
    /// hairlines are opacities of this, so the same ladder reads correctly in both themes.
    static let ink = dynamic(dark: rgb(238, 242, 248), light: rgb(26, 34, 48))

    static let text = ink
    static let muted = ink.opacity(0.55)
    static let soft = ink.opacity(0.42)

    static let accent = dynamic(dark: rgb(70, 200, 180), light: rgb(8, 122, 108))
    static let alert = dynamic(dark: rgb(255, 140, 114), light: rgb(190, 72, 60))
    static let live = accent

    // The mobile dashboard follows the current desktop treatment: a near-black page with graphite
    // cards, rather than the older navy shell.
    static let window = dynamic(dark: rgb(14, 15, 17), light: rgb(244, 246, 250))
    static let statsSurface = dynamic(dark: rgb(29, 30, 34), light: rgb(250, 251, 253))

    /// The hairline that *is* a card, and the same line that outlines the header pills.
    static let cardBorder = dynamic(dark: UIColor(white: 1, alpha: 0.12),
                                    light: UIColor(red: 26 / 255.0, green: 34 / 255.0,
                                                   blue: 48 / 255.0, alpha: 0.08))

    /// The tab bar: in dark the one surface deeper than the page; in light the same colour as the
    /// page, separated by nothing but the hairline.
    static let sidebar = dynamic(dark: rgb(20, 21, 24), light: rgb(243, 246, 251))

    /// A selected navigation item is a solid blue plate with white text, not an accent tint.
    static let navSelected = dynamic(dark: rgb(27, 87, 201), light: rgb(47, 123, 238))
    static let navSelectedText = Color.white

    /// The amber the design gives the headline rate — the top of the heatmap's ramp, so the busiest
    /// cell and the number over it are the same colour.
    static let rate = Color(hex: 0xFEAF01)

    static let streak = dynamic(dark: rgb(255, 129, 22), light: rgb(254, 100, 0))

    /// Corner radius shared by every card.
    static let cardRadius: CGFloat = 10
}
