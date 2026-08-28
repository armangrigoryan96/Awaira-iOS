import Foundation

/// The timing the user gets to choose, remembered across launches.
///
/// This is about how long the app waits before reacting, not about how it finds a touch — the
/// detection geometry stays at the Mac's numbers, see `ParityTests`.
///
/// The value is a computed property over a `@Published` box rather than a `@Published` property
/// with a `didSet`. Clamping needs to write the property from inside its own observer, and on a
/// property *wrapper* that re-enters the setter instead of being absorbed the way it is on a plain
/// stored property — it recurses until the stack runs out.
final class AppSettings: ObservableObject {

    /// Seconds a hand must stay on the face before Awaira shows its selected in-app cues.
    var buzzAfter: TimeInterval {
        get { storedBuzzAfter }
        set {
            let clamped = Self.clamp(buzzAfter: newValue)
            guard clamped != storedBuzzAfter else { return }
            storedBuzzAfter = clamped
            UserDefaults.standard.set(clamped, forKey: Self.buzzAfterKey)
        }
    }

    /// Level 2 exists only for parity with the Mac's escalation — nothing on the phone draws it —
    /// but it must stay below level 3 or the ladder reads backwards. Keeping the Mac's 2:3 ratio
    /// does that at any setting, and lands back on exactly 2.0 s when the buzz is at 3.0 s.
    var lingerAfter: TimeInterval { buzzAfter * 2.0 / 3.0 }

    @Published private var storedBuzzAfter: TimeInterval

    init() {
        // `double(forKey:)` reads a missing key as 0, which is a legal-looking value here — hence
        // `object(forKey:)`, so "never set" stays distinguishable from "set to zero".
        let saved = UserDefaults.standard.object(forKey: Self.buzzAfterKey) as? Double
        storedBuzzAfter = saved.map(Self.clamp(buzzAfter:)) ?? Self.defaultBuzzAfter
    }

    /// A second is about as short as this can usefully go: below the debounce (3 frames at ~5 fps)
    /// the buzz would arrive the instant the touch registers. Ten is long enough to only catch a
    /// hand that has properly settled.
    static let buzzAfterRange: ClosedRange<TimeInterval> = 1...10
    static let buzzAfterStep: TimeInterval = 0.5
    static let defaultBuzzAfter: TimeInterval = 3.0

    static func clamp(buzzAfter value: TimeInterval) -> TimeInterval {
        min(max(value, buzzAfterRange.lowerBound), buzzAfterRange.upperBound)
    }

    private static let buzzAfterKey = "buzzAfterSeconds"
}
