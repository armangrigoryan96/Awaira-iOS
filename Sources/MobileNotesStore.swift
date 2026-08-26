import Foundation

/// A free-form note — the user's own account of a moment, in their words rather than a chip's.
/// Stored locally, like everything else in Awaira; nothing here leaves the device.
///
/// Ported from `awaira/frontend/Sources/NotesStore.swift` under the phone's own key, so the two
/// apps' journals stay separate stores of the same shape.
struct MobileNote: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var text: String
    /// The chip the note was filed alongside, when there was one. Keeps a note findable from the
    /// context screen without duplicating the tally.
    var context: String?

    init(id: UUID = UUID(), date: Date = Date(), text: String, context: String? = nil) {
        self.id = id
        self.date = date
        self.text = text
        self.context = context
    }
}

/// UserDefaults-backed store for notes, newest first. A lightweight list rather than a database,
/// for what is a handful of short entries.
enum MobileNotesStore {
    static let storageKey = "awaira.mobile.notes.v1"

    static func load(defaults: UserDefaults = .standard) -> [MobileNote] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([MobileNote].self, from: data) else { return [] }
        return decoded.sorted { $0.date > $1.date }
    }

    /// Adds an entry. Returns `nil` for blank text so the caller can no-op.
    @discardableResult
    static func add(_ rawText: String, context: String? = nil, at date: Date = Date(),
                    defaults: UserDefaults = .standard) -> MobileNote? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var notes = load(defaults: defaults)
        let note = MobileNote(date: date, text: text, context: context)
        notes.insert(note, at: 0)
        persist(notes, defaults: defaults)
        return note
    }

    /// Blank text deletes the entry: an emptied note is a note the user took back.
    static func update(_ id: UUID, text rawText: String, defaults: UserDefaults = .standard) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        var notes = load(defaults: defaults)
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if text.isEmpty {
            notes.remove(at: index)
        } else {
            notes[index].text = text
        }
        persist(notes, defaults: defaults)
    }

    static func delete(_ id: UUID, defaults: UserDefaults = .standard) {
        var notes = load(defaults: defaults)
        notes.removeAll { $0.id == id }
        persist(notes, defaults: defaults)
    }

    private static func persist(_ notes: [MobileNote], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
