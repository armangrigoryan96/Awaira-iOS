import SwiftUI

/// One private, on-device reflection.
struct JournalEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let activity: String
    let note: String
}

final class JournalStore: ObservableObject {
    @Published private(set) var entries: [JournalEntry] = []
    private let key = "awaira.journal.v1"

    init() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([JournalEntry].self, from: data) else { return }
        entries = saved.sorted { $0.date > $1.date }
    }

    func add(activity: String, note: String) {
        let entry = JournalEntry(id: UUID(), date: Date(), activity: activity,
                                 note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        entries.insert(entry, at: 0)
        persist()
    }

    func addThought(_ text: String, title: String = "") {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let entry = JournalEntry(id: UUID(), date: Date(),
                                 activity: title.trimmingCharacters(in: .whitespacesAndNewlines), note: body)
        entries.insert(entry, at: 0)
        persist()
    }

    func delete(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: key)
    }
}

/// A calm private-notes surface: inviting at the top, reassuring in the middle, and intentionally
/// simple below so a reflection never has to compete with dashboard chrome.
struct MobileJournalView: View {
    @ObservedObject var journal: JournalStore
    @State private var composing = false
    @State private var expanded: Set<UUID> = []

    var body: some View {
        MobilePage(title: "Journal",
                   subtitle: "A private place to notice what matters.",
                   accessory: AnyView(MobileBrandRow { composeButton })) {
            reflectionPrompt
            privacyNote
            recentReflections
        }
        .sheet(isPresented: $composing) { JournalComposer(journal: journal) }
    }

    private var composeButton: some View {
        Button { composing = true } label: {
            Image(systemName: "square.and.pencil")
                .scaledFont(15)
                .foregroundStyle(AwairaPalette.accent)
                .frame(width: 34, height: 34)
                .background(AwairaPalette.window, in: Circle())
                .overlay(Circle().strokeBorder(AwairaPalette.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("composeEntry")
        .accessibilityLabel("Write a thought")
    }

    /// The invitation to write. Deliberately a plain card: it used to sit on a navy gradient behind
    /// a decorative swoosh with a glowing pencil over it, which is the one treatment the design
    /// rules out — "one restrained fill, a cool-blue hairline, and no shadow or glass effect", so
    /// that the content carries the contrast rather than the container.
    private var reflectionPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            MobileEyebrow(text: "A MOMENT TO REFLECT", tint: AwairaPalette.accent)
            Text("What\u{2019}s on your mind?")
                .awairaDisplay(25)
                .foregroundStyle(AwairaPalette.text)
            Text("Saved only on this iPhone.")
                .awairaCaption(14)
                .foregroundStyle(AwairaPalette.ink.opacity(0.55))
            Button("Write a thought") { composing = true }
                .buttonStyle(AwairaPrimaryButton())
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .awairaCard(padding: 16)
    }

    private var privacyNote: some View {
        HStack(spacing: 15) {
            Image(systemName: "lock.shield")
                .scaledFont(16)
                .foregroundStyle(AwairaPalette.ink.opacity(0.5))
            Text("Your reflections stay private, always on-device.")
                .awairaCaption(13)
                .foregroundStyle(AwairaPalette.ink.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .awairaCard(padding: 12)
    }

    private var recentReflections: some View {
        VStack(alignment: .leading, spacing: 14) {
            MobileEyebrow(text: "RECENT REFLECTIONS")
                .padding(.top, 7)
            if groups.isEmpty {
                MobileEmptyNote(text: "Your private moments will appear here when you choose to capture them.",
                                symbol: "square.and.pencil")
                    .awairaCard(padding: 18)
            } else {
                ForEach(groups, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 9) {
                        MobileEyebrow(text: Self.dayFormatter.string(from: group.day).uppercased())
                            .padding(.leading, 2)
                        entriesCard(group.entries)
                    }
                }
            }
        }
    }

    private func entriesCard(_ entries: [JournalEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                reflectionRow(entry)
                if index < entries.count - 1 {
                    Rectangle()
                        .fill(AwairaPalette.cardBorder.opacity(0.65))
                        .frame(height: 1)
                        .padding(.leading, 52)
                }
            }
        }
        .awairaCard(padding: 0)
    }

    private func reflectionRow(_ entry: JournalEntry) -> some View {
        let isExpanded = expanded.contains(entry.id)
        let title = entry.activity.isEmpty ? "Thought" : entry.activity
        let hasNote = !entry.note.isEmpty

        return Button {
            guard hasNote else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                if isExpanded { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 14) {
                    Circle().fill(entryColor(entry)).frame(width: 11, height: 11)
                    Text(title)
                        .scaledFont(19, weight: .medium)
                        .foregroundStyle(AwairaPalette.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Self.timeFormatter.string(from: entry.date))
                        .scaledFont(14)
                        .monospacedDigit()
                        .foregroundStyle(AwairaPalette.ink.opacity(0.50))
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .scaledFont(15, weight: .semibold)
                        .foregroundStyle(AwairaPalette.ink.opacity(0.55))
                }
                if hasNote && isExpanded {
                    Text(entry.note)
                        .awairaSubtitle(15)
                        .foregroundStyle(AwairaPalette.ink.opacity(0.64))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 25)
                } else if hasNote && entry.activity == "Other" {
                    Text(entry.note)
                        .awairaSubtitle(15)
                        .foregroundStyle(AwairaPalette.ink.opacity(0.52))
                        .lineLimit(1)
                        .padding(.leading, 25)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 17)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActionsCompat { journal.delete(entry) }
        .accessibilityLabel("\(title), \(Self.timeFormatter.string(from: entry.date))")
    }

    private func entryColor(_ entry: JournalEntry) -> Color {
        switch entry.activity.lowercased() {
        case "working": return AwairaPalette.rate
        case "other": return AwairaPalette.streak
        case "reading", "studying": return AwairaPalette.live
        default: return AwairaPalette.accent
        }
    }

    private var groups: [(day: Date, entries: [JournalEntry])] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: journal.entries) { calendar.startOfDay(for: $0.date) }
        return buckets.keys.sorted(by: >).map { ($0, buckets[$0] ?? []) }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE, MMMM d")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

/// Subtle overlapping strokes in the prompt card. They are code-native artwork, so they resolve
/// cleanly at every iPhone size and support the dark dashboard without a separate bitmap asset.
private struct JournalComposer: View {
    @ObservedObject var journal: JournalStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body_ = ""
    @FocusState private var bodyFocused: Bool

    private var canSave: Bool { !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Give it a name (optional)", text: $title)
                    .scaledFont(15, weight: .semibold)
                    .foregroundStyle(AwairaPalette.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(AwairaPalette.statsSurface,
                                in: RoundedRectangle(cornerRadius: AwairaPalette.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AwairaPalette.cardRadius, style: .continuous)
                        .strokeBorder(AwairaPalette.cardBorder, lineWidth: 1))

                ZStack(alignment: .topLeading) {
                    if body_.isEmpty {
                        Text("What's on your mind?")
                            .scaledFont(15)
                            .foregroundStyle(AwairaPalette.ink.opacity(0.35))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $body_)
                        .scaledFont(15)
                        .foregroundStyle(AwairaPalette.text)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .focused($bodyFocused)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(AwairaPalette.statsSurface,
                            in: RoundedRectangle(cornerRadius: AwairaPalette.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AwairaPalette.cardRadius, style: .continuous)
                    .strokeBorder(AwairaPalette.cardBorder, lineWidth: 1))

                Text("Saved only on this iPhone. Never uploaded or shared.")
                    .scaledFont(12)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.45))
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AwairaPalette.window.ignoresSafeArea())
            .navigationTitle("New entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(AwairaPalette.ink.opacity(0.75))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { journal.addThought(body_, title: title); dismiss() }
                        .foregroundStyle(canSave ? AwairaPalette.accent : AwairaPalette.ink.opacity(0.3))
                        .disabled(!canSave)
                        .accessibilityIdentifier("saveEntry")
                }
            }
        }
        .presentationBackground(AwairaPalette.window)
        .onAppear { bodyFocused = true }
    }
}

private extension View {
    /// A delete affordance that works outside a `List`, where `swipeActions` does nothing. A long
    /// press is the discoverable gesture here; the confirmation is what keeps it from being a way to
    /// lose a note by accident.
    func swipeActionsCompat(delete: @escaping () -> Void) -> some View {
        modifier(DeletableRow(delete: delete))
    }
}

private struct DeletableRow: ViewModifier {
    let delete: () -> Void
    @State private var confirming = false

    func body(content: Content) -> some View {
        content
            .onLongPressGesture { confirming = true }
            .confirmationDialog("Delete this entry?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            }
    }
}
