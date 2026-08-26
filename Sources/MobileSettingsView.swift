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

/// Settings, now a tab of its own rather than a sheet over Today. Still a native `Form`: the
/// redesign covers the dashboard, and repainting the controls is a separate piece of work.
struct MobileSettingsView: View {
    @ObservedObject var detector: Detector
    @ObservedObject var settings: AppSettings
    @ObservedObject var license: MobileLicenseManager
    @Binding var vibrateEnabled: Bool
    @Binding var voiceEnabled: Bool
    @Binding var blurEnabled: Bool

    @AppStorage("mobileAppearance") private var appearance = MobileAppearance.system.rawValue
    @AppStorage(MobileGoal.storageKey) private var goalRate = MobileGoal.defaultRate

    /// What the theme row shows on its right-hand side, falling back to System for a value the app
    /// no longer recognises.
    private var selectedAppearance: MobileAppearance {
        MobileAppearance(rawValue: appearance) ?? .system
    }

    var body: some View {
        NavigationStack {
            Form {
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
                    Text("Dark keeps the dashboard on the design's near-black; System follows iOS.")
                }

                Section {
                    // Same shape as the Theme row above, and for the same reasons: a dropdown
                    // anchored to the value at the right edge, without the menu style's ⌃⌄ glyph.
                    LabeledContent("Touches per hour") {
                        Menu {
                            Picker("Touches per hour", selection: $goalRate) {
                                ForEach(MobileGoal.choices, id: \.self) { option in
                                    Text(String(format: "%.0f/hr", option)).tag(option)
                                }
                            }
                        } label: {
                            Text(String(format: "Under %.0f/hr", goalRate))
                                .foregroundStyle(AwairaPalette.ink.opacity(0.55))
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("goalRatePicker")
                    }
                } header: {
                    Text("Goal")
                } footer: {
                    Text("Today measures your rate against this. It starts from your onboarding estimate — move it once you've seen a few real days.")
                }

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

                Section("Timing") {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Floating bar thickness", value: thicknessValueLabel)
                        Slider(value: $detector.pipThickness,
                               in: PipWindow.thicknessRange,
                               step: PipWindow.thicknessStep)
                            .accessibilityIdentifier("barThicknessSlider")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Buzz after", value: String(format: "%.1f seconds", settings.buzzAfter))
                        Slider(value: $settings.buzzAfter,
                               in: AppSettings.buzzAfterRange,
                               step: AppSettings.buzzAfterStep)
                            .accessibilityIdentifier("buzzDelaySlider")
                    }
                }

                licenceSection

                Section {
                    // The app watches this key, so clearing it drops straight back into onboarding.
                    Button("Replay onboarding", systemImage: "arrow.counterclockwise") {
                        UserDefaults.standard.set(0, forKey: "awairaOnboardingVersion")
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .tint(AwairaPalette.accent)
    }

    @ViewBuilder private var licenceSection: some View {
        Section {
            if case .valid(let plan, let expires) = license.state {
                LabeledContent("Plan", value: plan.capitalized)
                LabeledContent("Status", value: expiryText(expires, plan: plan))
                Button("Refresh licence") { Task { await license.recheck() } }
                    .disabled(license.checking)
                Button("Remove licence", role: .destructive) { license.removeLicense() }
            } else {
                Text("No active licence on this iPhone.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Licence")
        } footer: {
            Text("A licence can be active on one device at a time.")
        }
    }

    private var thicknessValueLabel: String {
        let requested = String(format: "%.0f pt", detector.pipThickness)
        guard let size = detector.pipWindowSize else { return requested }
        return requested + String(format: " (%.0f pt shown)", min(size.width, size.height))
    }

    private func expiryText(_ expires: Date?, plan: String) -> String {
        guard let expires, plan.lowercased() != "lifetime" else { return "Active" }
        return "Renews \(expires.formatted(date: .abbreviated, time: .omitted))"
    }
}
