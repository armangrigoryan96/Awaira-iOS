import SwiftUI

/// "What was happening?": the chips that turn a count into something the user can act on, plus a
/// line of their own words if a chip is not enough.
///
/// The card is always on the page, as on the Mac, and dims when there is no recent touch to attach
/// context to — so its place never moves and the page does not reflow every time a hand comes down.
struct WhatWasHappeningCard: View {
    /// The touch being asked about, or `nil` when there is nothing recent enough.
    let prompt: MobileContextPrompt?
    /// Today's answers so far, so a chip already picked this hour reads as familiar rather than new.
    let counts: [String: Int]
    let onAnswer: (MobileContextChoice, String) -> Void
    let onOpenDetail: () -> Void

    /// Held only until the answer is filed — the card is a question about one moment, not a form
    /// with a saved state.
    @State private var selected: MobileContextChoice?
    @State private var note = ""
    @State private var showingNote = false
    @State private var customLabel = ""
    @State private var showingCustom = false
    /// Re-read after "Other…" adds a label, so the new chip appears without waiting for a redraw
    /// from somewhere else.
    @State private var choices = MobileContextOptions.choices()

    /// Idle chips have to say "there is nothing to tag right now" while staying readable on the
    /// design's dark card — the Mac settled on 0.6 for the same reason.
    private static let idleOpacity = 0.6

    private var idle: Bool { prompt == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow

            chipRows
                .opacity(idle ? Self.idleOpacity : 1)
                .disabled(idle)

            noteRow
                .opacity(idle ? Self.idleOpacity : 1)
                .disabled(idle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .awairaCard(padding: 14)
        .animation(.easeInOut(duration: 0.18), value: idle)
        .onChange(of: prompt?.id) { _, _ in
            // A new moment is a new question: nothing of the last answer carries over.
            selected = nil
            note = ""
        }
        .alert("Add a context", isPresented: $showingCustom) {
            TextField("What were you doing?", text: $customLabel)
            Button("Cancel", role: .cancel) { customLabel = "" }
            Button("Add") { addCustomLabel() }
        } message: {
            Text("It joins your chips, so you can pick it with one tap next time.")
        }
        .sheet(isPresented: $showingNote) { noteSheet }
    }

    // MARK: - Chrome

    private var titleRow: some View {
        Button(action: onOpenDetail) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("WHAT WAS HAPPENING?")
                        .font(.system(size: 11, weight: .medium))
                        .kerning(0.6)
                        .foregroundStyle(AwairaPalette.ink.opacity(0.72))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AwairaPalette.ink.opacity(0.45))
                }
                Text(idle ? "Chips wake up after your next touch."
                          : "Add context to this moment")
                    .font(.system(size: 13))
                    .foregroundStyle(AwairaPalette.ink.opacity(0.55))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("contextDetail")
    }

    // MARK: - Chips

    /// Laid out by hand rather than in a `LazyVGrid`: the labels are the user's own words and vary
    /// wildly in length, so equal columns would either clip "Watching videos" or leave a lake of
    /// space beside "Math". These wrap on their natural width instead.
    private var chipRows: some View {
        FlowLayout(spacing: 8) {
            ForEach(choices) { choice in
                chip(choice)
            }
        }
    }

    private func chip(_ choice: MobileContextChoice) -> some View {
        let isSelected = selected == choice
        return Button {
            if choice.isOther {
                showingCustom = true
            } else {
                answer(choice)
            }
        } label: {
            HStack(spacing: 6) {
                Text(choice.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                }
                // A tally the user has already built today, so the chips are not a blank slate
                // every time — but only where there is one, so the row stays quiet on a new day.
                if !isSelected, let count = counts[choice.id], count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(AwairaPalette.ink.opacity(0.45))
                }
            }
            .foregroundStyle(isSelected ? AwairaPalette.navSelectedText : AwairaPalette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? AwairaPalette.navSelected : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? .clear : AwairaPalette.ink.opacity(0.16),
                                            lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("contextChip.\(choice.id)")
    }

    // MARK: - Note

    private var noteRow: some View {
        Button {
            showingNote = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: note.isEmpty ? "square" : "checkmark.square.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(note.isEmpty ? AwairaPalette.ink.opacity(0.35)
                                                  : AwairaPalette.accent)
                Text(note.isEmpty ? "Add a note" : note)
                    .font(.system(size: 14))
                    .foregroundStyle(note.isEmpty ? AwairaPalette.navSelected : AwairaPalette.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("contextNote")
    }

    private var noteSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("What was going on?", text: $note, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(3...8)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(AwairaPalette.statsSurface,
                                in: RoundedRectangle(cornerRadius: AwairaPalette.cardRadius,
                                                     style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AwairaPalette.cardRadius,
                                              style: .continuous)
                        .strokeBorder(AwairaPalette.cardBorder, lineWidth: 1))

                Text("Saved on this iPhone only, alongside the chip you pick.")
                    .font(.system(size: 12))
                    .foregroundStyle(AwairaPalette.soft)
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(AwairaPalette.window.ignoresSafeArea())
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { note = ""; showingNote = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingNote = false }
                }
            }
        }
        .tint(AwairaPalette.accent)
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    /// Picking a chip *is* the answer — there is no save button, because a question with one tap in
    /// it should not need two. The tick shows for a beat before the prompt clears.
    private func answer(_ choice: MobileContextChoice) {
        withAnimation(.easeInOut(duration: 0.15)) { selected = choice }
        onAnswer(choice, note)
    }

    private func addCustomLabel() {
        guard let choice = MobileContextOptions.addCustomLabel(customLabel) else {
            customLabel = ""
            return
        }
        customLabel = ""
        choices = MobileContextOptions.choices()
        answer(choice)
    }
}

/// Wraps its children onto as many rows as they need, each at its own width.
///
/// SwiftUI has no built-in flow layout, and the alternatives both fail these chips: a `LazyVGrid`
/// forces every chip to a column's width, and an `HStack` with `.lineLimit(1)` truncates rather
/// than wrapping.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(subviews, in: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, in: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(_ subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, needed > width {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
