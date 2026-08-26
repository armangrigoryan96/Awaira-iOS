import Foundation

/// What the user was doing when a touch happened — the vocabulary behind the "What was happening?"
/// card, and the moment an answer belongs to.
///
/// The Mac ships a fixed list (Stress, Boredom, Anxiety, …) because its onboarding never asks. The
/// phone's does: `IPhoneOnboardingView`'s `contexts` question already collects "While thinking",
/// "Studying", "Watching videos", "Reading" and the rest, in the user's own words. Reusing those
/// answers means the chips read like the user's day from the very first touch, instead of asking
/// them to translate it into someone else's categories.

/// One chip. `id` is what gets stored, `label` is what gets shown — a custom label can be renamed
/// or dropped without orphaning the days that were filed under it.
struct MobileContextChoice: Identifiable, Hashable {
    let id: String
    let label: String

    var isOther: Bool { id == MobileContextOptions.otherID }
}

/// A touch waiting to be given context. Held for a few minutes and then let go: an answer is only
/// worth storing while the user still remembers the moment it is about.
struct MobileContextPrompt: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
}

enum MobileContextOptions {
    /// Where the user's own labels live. The onboarding answer is read, never written, so replaying
    /// onboarding cannot wipe a label the user typed into the card.
    static let customKey = "awaira.mobile.contextLabels"

    /// The onboarding question this vocabulary comes from.
    static let onboardingKey = "contexts"

    static let otherID = "other"

    /// How many named chips the card shows. Five slots on a phone's card width, and the last is
    /// always "Other…", so four are named. New labels enter at the end and the oldest rolls out
    /// rather than making the card taller — the same rule as the Mac's `TriggerOptionsStore`.
    static let visibleCount = 4

    /// What a user who skipped the contexts question gets. Deliberately broad: these are prompts to
    /// think with, not a taxonomy to be accurate about.
    static let fallbackLabels = ["Working", "Thinking", "Reading", "Stressed"]

    /// The chips to show, oldest first, with "Other…" always last.
    static func choices(defaults: UserDefaults = .standard) -> [MobileContextChoice] {
        let named = (onboardingLabels(defaults: defaults) + customLabels(defaults: defaults))
        let visible = named.isEmpty ? fallbackLabels : Array(named.suffix(visibleCount))
        return visible.map { MobileContextChoice(id: id(for: $0), label: $0) }
             + [MobileContextChoice(id: otherID, label: "Other…")]
    }

    /// The contexts picked during onboarding. Stored comma-joined by `IPhoneOnboardingView.finish`.
    static func onboardingLabels(defaults: UserDefaults = .standard) -> [String] {
        (defaults.string(forKey: onboardingKey) ?? "")
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func customLabels(defaults: UserDefaults = .standard) -> [String] {
        guard let data = defaults.data(forKey: customKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return decoded
    }

    /// Files a label typed into "Other…", and returns the chip it became.
    ///
    /// A label matching one already on offer resolves to that chip instead of being stored twice —
    /// otherwise the same word would appear as two chips with separate tallies.
    @discardableResult
    static func addCustomLabel(_ raw: String, defaults: UserDefaults = .standard) -> MobileContextChoice? {
        guard let label = normalized(raw) else { return nil }
        let existing = onboardingLabels(defaults: defaults) + customLabels(defaults: defaults)
        if let match = existing.first(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
            return MobileContextChoice(id: id(for: match), label: match)
        }

        var labels = customLabels(defaults: defaults)
        labels.append(label)
        // Only as many as could ever be shown are kept: a label that has rolled off the card can no
        // longer be picked, so storing it forever would grow the list with nothing to answer for it.
        if labels.count > visibleCount { labels.removeFirst(labels.count - visibleCount) }
        if let data = try? JSONEncoder().encode(labels) { defaults.set(data, forKey: customKey) }
        return MobileContextChoice(id: id(for: label), label: label)
    }

    /// A stable id for a label. Case- and punctuation-insensitive, so "Piano class" and
    /// "piano class" are the same chip.
    static func id(for label: String) -> String {
        let slug = label.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")
        return slug.isEmpty ? otherID : slug
    }

    /// The label as it will be stored: collapsed whitespace, capitalised, and short enough for a
    /// chip. `nil` for anything blank.
    static func normalized(_ raw: String) -> String? {
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(24))
    }

    /// How a stored id should be named on a later screen, given what is on offer now. Falls back to
    /// un-slugging the id, so a day filed under a label that has since rolled off the card still
    /// reads as words rather than as "piano-class".
    static func label(for id: String, defaults: UserDefaults = .standard) -> String {
        // Before the chip lookup: the chip's own label carries an ellipsis because it opens a text
        // field, and "filed under Other…" would read as a truncation rather than as a category.
        if id == otherID { return "Other" }
        if let match = choices(defaults: defaults).first(where: { $0.id == id }) { return match.label }
        let words = id.split(separator: "-").map(String.init).joined(separator: " ")
        return words.isEmpty ? id : words.prefix(1).uppercased() + words.dropFirst()
    }
}
