import SwiftUI

/// Light, dark, or whatever the phone is set to. The dashboard is painted from `AwairaPalette`,
/// which resolves against the view's colour scheme, so this repaints the whole app.
enum MobileAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// `nil` hands the decision back to iOS.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Settings. A native `Form` — its grouping and its controls are the right ones on a phone — but
/// dressed in the app's own surfaces rather than iOS's grouped grey: the page colour behind it, the
/// card colour under each section, and the palette's hairline between rows.
struct MobileSettingsView: View {
    @ObservedObject var detector: Detector
    @ObservedObject var settings: AppSettings
    @ObservedObject var journal: JournalStore
    @Binding var vibrateEnabled: Bool
    @Binding var voiceEnabled: Bool
    @Binding var blurEnabled: Bool

    @AppStorage("mobileAppearance") private var appearance = MobileAppearance.dark.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDataDeletion = false

    /// What the theme row shows on its right-hand side, falling back to System for a value the app
    /// no longer recognises.
    private var selectedAppearance: MobileAppearance {
        MobileAppearance(rawValue: appearance) ?? .system
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MobilePageTitle(title: "Settings")
                        .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))

                Section {
                    // A `Menu` wrapping the picker rather than `.pickerStyle(.menu)` on it: the
                    // menu style stamps a ⌃⌄ glyph beside the value that cannot be turned off, and
                    // the row reads cleaner without it. The dropdown itself is unchanged — same
                    // list, same checkmark on the current choice.
                    //
                    // Only the value is inside the menu's label, with the title left to
                    // `LabeledContent`. iOS anchors the popup to whatever the label covers, so a
                    // full-width label put it in the middle of the screen; this keeps it under the
                    // word it belongs to, at the right edge.
                    LabeledContent("Theme") {
                        Menu {
                            Picker("Theme", selection: $appearance) {
                                ForEach(MobileAppearance.allCases) { option in
                                    Text(option.title).tag(option.rawValue)
                                }
                            }
                        } label: {
                            Text(selectedAppearance.title)
                                .foregroundStyle(AwairaPalette.ink.opacity(0.55))
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("appearancePicker")
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Dark keeps the dashboard on the design's near-black page; System follows iOS.")
                }
                .listRowBackground(AwairaPalette.statsSurface)

                Section {
                    Toggle("Vibrate", isOn: $vibrateEnabled)
                        .accessibilityIdentifier("alertToggle.Vibrate")
                    Toggle("Voice", isOn: $voiceEnabled)
                        .accessibilityIdentifier("alertToggle.Voice")
                    Toggle("Blur screen", isOn: $blurEnabled)
                        .accessibilityIdentifier("alertToggle.Blur screen")
                } header: {
                    Text("When a hand lingers")
                } footer: {
                    Text("Choose the cues that feel helpful. You can change them at any time.")
                }
                .listRowBackground(AwairaPalette.statsSurface)

                Section("Timing") {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Buzz after", value: String(format: "%.1f seconds", settings.buzzAfter))
                        Slider(value: $settings.buzzAfter,
                               in: AppSettings.buzzAfterRange,
                               step: AppSettings.buzzAfterStep)
                            .accessibilityIdentifier("buzzDelaySlider")
                    }
                }
                .listRowBackground(AwairaPalette.statsSurface)

                Section {
                    // The app watches this key, so clearing it drops straight back into onboarding.
                    Button("Replay onboarding", systemImage: "arrow.counterclockwise") {
                        UserDefaults.standard.set(0, forKey: "awairaOnboardingVersion")
                    }
                }
                .listRowBackground(AwairaPalette.statsSurface)

                Section {
                    Button("Delete all local data", systemImage: "trash", role: .destructive) {
                        confirmingDataDeletion = true
                    }
                } header: {
                    Text("Local data")
                } footer: {
                    Text("Erases this iPhone's saved history, journal, badges, learning progress, and settings. Camera frames are never stored.")
                }
                .listRowBackground(AwairaPalette.statsSurface)

                Section("Privacy & legal") {
                    Text("Camera frames, detections, and your journal stay on this iPhone. Opening Learn loads an Awaira article in the app; Awaira does not use advertising pixels on those pages.")
                        .font(.footnote)
                        .foregroundStyle(AwairaPalette.ink.opacity(0.68))
                    Link("Privacy Policy", destination: MobileLegal.privacy)
                    Link("Terms of Use", destination: MobileLegal.terms)
                }
                .listRowBackground(AwairaPalette.statsSurface)
            }
            .scrollContentBackground(.hidden)
            .background(AwairaPalette.window.ignoresSafeArea())
            .listSectionSpacing(.compact)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AwairaPalette.window, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AwairaPalette.accent)
                }
            }
        }
        .tint(AwairaPalette.accent)
        .presentationBackground(AwairaPalette.window)
        .alert("Delete all local data?", isPresented: $confirmingDataDeletion) {
            Button("Delete", role: .destructive) { deleteLocalData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes Awaira data stored on this iPhone. It cannot be undone.")
        }
    }

    private func deleteLocalData() {
        detector.deleteLocalData()
        journal.deleteAll()
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }
    }

}

private enum MobileLegal {
    static let privacy = URL(string: "https://awaira.app/privacy")!
    static let terms = URL(string: "https://awaira.app/terms")!
}
