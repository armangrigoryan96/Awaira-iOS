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

    /// Sampled from Awaira's blue app mark. It owns the neutral, measurable product language:
    /// dashboard figures, selected controls, and progress.
    ///
    /// This used to be the teal below, which made the phone disagree with the Mac on the one colour
    /// the product is named by — and left green doing two jobs at once. Green is now only ever the
    /// literal live/on-device state, exactly as on the desktop.
    static let accent = dynamic(dark: rgb(37, 160, 231), light: rgb(19, 113, 181))
    static let alert = dynamic(dark: rgb(255, 140, 114), light: rgb(190, 72, 60))

    /// Reserved for the literal live/on-device state — the camera dot, and nothing else.
    static let live = dynamic(dark: rgb(29, 198, 178), light: rgb(8, 122, 108))

    /// The quiet slate the desktop gives a figure that is data rather than status.
    static let figure = Color(red: 138.0 / 255.0, green: 160.0 / 255.0, blue: 187.0 / 255.0)

    /// The warm, optimistic blue used by the first-run experience. It is deliberately separate from
    /// the product accent, whose higher saturation is intended for controls and data.
    static let onboardingBlue = Color(red: 37.0 / 255.0, green: 82.0 / 255.0, blue: 151.0 / 255.0)

    /// First-run text/line colour. Onboarding always paints the light paper illustration, so its
    /// type must stay dark even on a phone set to the dark theme — which is why these three cannot
    /// be `dynamic`, unlike everything above them.
    static let onboardingInk = Color(red: 26.0 / 255.0, green: 34.0 / 255.0, blue: 48.0 / 255.0)

    /// The light backdrop behind first-run badges, for the same reason as `onboardingInk`.
    static let onboardingCanvas = Color(red: 244.0 / 255.0, green: 246.0 / 255.0, blue: 250.0 / 255.0)

    // The mobile dashboard follows the current desktop treatment: a near-black page with graphite
    // cards, rather than the older navy shell.
    static let window = dynamic(dark: rgb(14, 15, 17), light: rgb(244, 246, 250))
    static let statsSurface = dynamic(dark: rgb(29, 30, 34), light: rgb(250, 251, 253))

    /// The hairline that *is* a card, and the same line that outlines the header pills.
    static let cardBorder = dynamic(dark: rgb(48, 53, 63),
                                    light: UIColor(red: 26 / 255.0, green: 34 / 255.0,
                                                   blue: 48 / 255.0, alpha: 0.08))

    /// The tab bar. On the Mac the navigation rail is the *raised* graphite surface above the black
    /// workspace; the phone's bar now matches it, rather than being the one surface deeper than the
    /// page. That is what lets the selected tab read as an opening cut through the bar.
    static let sidebar = dynamic(dark: rgb(34, 35, 39), light: rgb(233, 237, 245))

    /// An active tab opens into the same canvas as the page above it, so the selected destination
    /// feels like an intentional cut-out of the bar rather than a second, competing blue button.
    static let navSelected = window
    static let navSelectedText = ink

    /// The amber the design gives the headline rate — the top of the heatmap's ramp, so the busiest
    /// cell and the number over it are the same colour.
    static let rate = Color(hex: 0xFEAF01)

    static let streak = dynamic(dark: rgb(255, 129, 22), light: rgb(254, 100, 0))

    /// Corner radius shared by every card: modestly softened, never pill-like.
    static let cardRadius: CGFloat = 9
}
