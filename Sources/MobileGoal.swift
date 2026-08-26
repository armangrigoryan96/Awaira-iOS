import Foundation

/// The gentle target the Today page measures the day against: approaches per tracked hour.
///
/// Stored under the same key the Mac uses (`frontend/Sources/Sections.swift`), so the two apps
/// describe a goal the same way. They are separate sandboxes, so nothing is shared at runtime —
/// this is about the two codebases agreeing on the unit, not about syncing a value.
enum MobileGoal {
    static let storageKey = "goalRatePerHour"

    /// What the Mac ships with, and what a user who skipped or fumbled the estimate gets.
    static let defaultRate = 20.0

    /// The values the Settings row offers. A ladder rather than a slider: the number is a rough
    /// intention, and a slider invites fiddling with a precision the measurement does not have.
    static let choices: [Double] = [2, 3, 5, 8, 10, 15, 20, 25, 30, 40, 60, 80]

    /// Writes a starting goal the first time the app looks for one, so a new user is not asked to
    /// invent a number before they have seen a single reading.
    ///
    /// Only ever writes when the key is absent — an existing choice, including one that happens to
    /// equal the default, is never overwritten.
    static func seedIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: storageKey) == nil else { return }
        defaults.set(seedRate(from: defaults.string(forKey: "frequencyEstimate")), forKey: storageKey)
    }

    /// A starting goal derived from the onboarding estimate
    /// (`IPhoneOnboardingView`'s `frequencyEstimate` question).
    ///
    /// It is a starting point and nothing more, because the two numbers do not measure the same
    /// thing: onboarding asks how often the *habit* happens in a day, while the dashboard counts
    /// every hand approach to the face in an hour — a far larger figure. So this maps the answer
    /// onto the ladder monotonically (a heavier estimate starts higher) rather than converting it,
    /// and the user is expected to move it once they have a real reading to look at.
    static func seedRate(from frequencyEstimate: String?) -> Double {
        switch frequencyEstimate {
        case "A few times":     return 8
        case "Around 10–30":    return 15
        case "Around 30–100":   return 25
        case "More than 100":   return 40
        default:                return defaultRate  // "I honestly don't know", or no answer at all
        }
    }
}
