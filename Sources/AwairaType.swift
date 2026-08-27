import SwiftUI

// One place for the app's type roles, ported from `awaira/frontend/Sources/AwairaType.swift`, so a
// heading can't drift into being 17pt on one card and 18 on the next — which is exactly what the
// phone had before this file existed: a 39pt page title on Patterns beside a 28pt one on Today.
//
// Every helper builds on `scaledFont`, and every helper sets font and letterfit only — colour stays
// with the call site, which is what decides whether a title is ink, accent or alert.

// MARK: - Dynamic Type

/// Fixed `.system(size:)` fonts ignore Dynamic Type, so on their own the big dashboard numbers
/// would stay put while the semantic text around them grew. This closes that gap the way the Mac's
/// `scaledFont` does for ⌘+ / ⌘-, but driven by the iOS accessibility setting instead.
///
/// The multiplier is deliberately gentler than the system's own: this is a dense dashboard of
/// side-by-side figures, and at the full accessibility ramp a 52pt serif number simply cannot share
/// a row with anything. Semantic text (`.caption`, `.body`) still scales the whole way — only these
/// fixed-size roles are damped.
private struct ScaledSystemFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    private var factor: CGFloat {
        switch typeSize {
        case .xSmall:  return 0.88
        case .small:   return 0.94
        case .medium:  return 1.00
        case .large:   return 1.00
        case .xLarge:  return 1.07
        case .xxLarge: return 1.14
        case .xxxLarge: return 1.22
        default:       return 1.32   // the five accessibility sizes, clamped to one step
        }
    }

    func body(content: Content) -> some View {
        content.font(.system(size: (size * factor).rounded(), weight: weight, design: design))
    }
}

extension View {
    /// Drop-in replacement for `.font(.system(size:weight:design:))` that also honours the phone's
    /// text size. Same argument order as `Font.system`, and the same name as the Mac's helper so
    /// ported code reads identically on both platforms.
    func scaledFont(_ size: CGFloat,
                    weight: Font.Weight = .regular,
                    design: Font.Design = .default) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design))
    }
}

// MARK: - Roles

extension View {
    /// Page titles: the date on Today, and the heading of every tab. Serif at a regular weight is
    /// the app's voice, and it is copied verbatim from the Mac's `AwairaType.swift` — "a bold sans
    /// heading over the same content reads like a dashboard, and the point of the redesign is that
    /// it doesn't". Changing this one function is enough to make every page in the app stop looking
    /// like Awaira, because every page title goes through it.
    func awairaDisplay(_ size: CGFloat = 28) -> some View {
        scaledFont(size, weight: .regular, design: .serif)
            .tracking(-0.2)
    }

    /// The line under a page title.
    func awairaSubtitle(_ size: CGFloat = 15) -> some View {
        scaledFont(size)
    }

    /// The title of a card. Slightly tightened: at 17pt the system's default letterfit is loose
    /// enough that two-word titles look spaced out beside the serif figures.
    func awairaCardTitle(_ size: CGFloat = 17) -> some View {
        scaledFont(size, weight: .semibold)
            .tracking(-0.25)
    }

    /// A headline figure — the per-hour rate, a day's number. Serif and monospaced so a number that
    /// ticks up doesn't shuffle the ones beside it.
    func awairaFigure(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        scaledFont(size, weight: weight, design: .serif)
            .monospacedDigit()
    }

    /// A small stat: bar values, popover rows. Sans, because these sit in tight rows where serif
    /// digits at 15pt get muddy, but still monospaced for the same reason as above.
    func awairaStat(_ size: CGFloat = 15) -> some View {
        scaledFont(size, weight: .semibold)
            .monospacedDigit()
    }

    /// The small all-caps label above a card's content — PER HOUR, AWARENESS PROGRESS. The wide
    /// letterfit is most of what makes an eyebrow read as one.
    func awairaEyebrow(_ size: CGFloat = 11, tracking: CGFloat = 1.4) -> some View {
        scaledFont(size, weight: .semibold)
            .tracking(tracking)
    }

    /// The caption under a figure or beside a control.
    func awairaCaption(_ size: CGFloat = 13) -> some View {
        scaledFont(size)
            .tracking(0.1)
    }
}
