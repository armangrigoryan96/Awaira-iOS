import SwiftUI

/// The main app surface deliberately leans on iOS navigation, lists, and controls. Detection
/// stays visually quiet so the information people need is easy to scan at a glance.
struct ContentView: View {
    @StateObject private var detector = Detector()
    @StateObject private var settings = AppSettings()
    @EnvironmentObject private var license: MobileLicenseManager
    @State private var showSettings = false
    @State private var cameraRequested = false
    @State private var selectedTab: MobileAppTab = .dashboard
    @State private var weekMode: WeekChartMode = .total

    @AppStorage("mobileVibrateEnabled") private var vibrateEnabled = true
    @AppStorage("mobileVoiceEnabled") private var voiceEnabled = false
    @AppStorage("mobileBlurEnabled") private var blurEnabled = true

    private var isUITest: Bool { ProcessInfo.processInfo.arguments.contains("-UITest") }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                dashboard
                    .tabItem { Label("Today", systemImage: "house") }
                    .tag(MobileAppTab.dashboard)

                MobileInsightsView(detector: detector)
                    .tabItem { Label("Insights", systemImage: "chart.bar") }
                    .tag(MobileAppTab.insights)

                MobileLearnLibrary()
                    .tabItem { Label("Learn", systemImage: "book.closed") }
                    .tag(MobileAppTab.learn)
            }
            .tint(.indigo)

            // The source view is present only to support the system PiP window. It never exposes
            // a camera frame in Awaira's interface.
            CameraDisplayView(display: detector.display, showsVideo: false)
                .ignoresSafeArea()
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            DimOverlay(active: blurEnabled && detector.touchLevel >= 3)
            TouchBorder(level: detector.touchLevel)
        }
        .sheet(isPresented: $showSettings) {
            MobileSettingsView(detector: detector,
                               settings: settings,
                               license: license,
                               vibrateEnabled: $vibrateEnabled,
                               voiceEnabled: $voiceEnabled,
                               blurEnabled: $blurEnabled)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            applyTiming()
            applyAlerts()
        }
        .onChange(of: settings.buzzAfter) { _, _ in applyTiming() }
        .onChange(of: vibrateEnabled) { _, _ in applyAlerts() }
        .onChange(of: voiceEnabled) { _, _ in applyAlerts() }
        .onChange(of: detector.touchLevel) { _, level in
            if level == 1 { TouchSound.play() }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var dashboard: some View {
        NavigationStack {
            List {
                if let errorText = detector.errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    if !cameraRequested && !isUITest {
                        cameraStartRow
                    } else {
                        Label(status, systemImage: statusSymbol)
                            .foregroundStyle(statusColor)
                            .accessibilityIdentifier("statusLine")
                    }
                } footer: {
                    Text("Camera frames are processed live on this iPhone and are never recorded or uploaded.")
                }

                Section("Today") {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Today: \(detector.count)")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .accessibilityIdentifier("todayCount")
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1f", todayRate))
                                .font(.title2.weight(.semibold))
                                .monospacedDigit()
                            Text("per tracked hour")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(todayInsight)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("This week") {
                    HStack(spacing: 0) {
                        stat(value: "\(detector.weeklyTotal)", label: "interruptions")
                        Divider().frame(height: 42)
                        stat(value: String(format: "%.1f", detector.weeklyRate), label: "per hour")
                        Divider().frame(height: 42)
                        stat(value: trackedTime, label: "tracked today")
                    }
                    .padding(.vertical, 4)

                    Picker("Chart", selection: $weekMode) {
                        ForEach(WeekChartMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("weekModePicker")

                    MobileWeekChart(days: detector.week, mode: weekMode)
                        .frame(height: 132)
                        .padding(.vertical, 4)

                    Text(weeklyTrendText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Recent activity") {
                    LabeledContent("Last interruption", value: lastActivityText)
                }

                Section {
                    NavigationLink {
                        MobileInsightsView(detector: detector)
                    } label: {
                        Label("View patterns and insights", systemImage: "chart.xyaxis.line")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                        .accessibilityIdentifier("settingsToggle")
                }
            }
        }
    }

    private var cameraStartRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Camera is off", systemImage: "camera")
                .font(.headline)
            Text("Start it when you are ready. Awaira looks only for hand-to-face movement; video never leaves this iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Start camera", systemImage: "play.fill", action: startCamera)
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("cameraStartCard")
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private func startCamera() {
        cameraRequested = true
        applyTiming()
        detector.start()
    }

    private func applyTiming() {
        detector.level3After = settings.buzzAfter
        detector.level2After = settings.lingerAfter
    }

    private func applyAlerts() {
        detector.vibrateEnabled = vibrateEnabled
        detector.voiceEnabled = voiceEnabled
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var todayRate: Double {
        MobileStatsStore.hourlyRate(interruptions: detector.count, activeSeconds: detector.activeSecondsToday)
    }

    private var trackedTime: String {
        let seconds = Int(detector.activeSecondsToday.rounded())
        if seconds < 60 { return "< 1 min" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return String(format: "%dh %02dm", seconds / 3600, (seconds % 3600) / 60)
    }

    private var weeklyTrendText: String {
        guard let change = detector.weeklyImprovement, abs(change) >= 1 else {
            return "Your rolling seven-day total. Data stays on this iPhone."
        }
        let amount = Int(abs(change).rounded())
        return change > 0 ? "\(amount)% lower than the previous week." : "\(amount)% higher than the previous week."
    }

    private var todayInsight: String {
        guard detector.count > 0 else { return "Your activity will appear here as you use Awaira." }
        guard detector.preventedPulls > 0 else { return "Every detected moment helps build awareness." }
        return "You released \(detector.preventedPulls) moment\(detector.preventedPulls == 1 ? "" : "s") before the feedback delay."
    }

    private var lastActivityText: String {
        guard let date = detector.lastDetection else { return "No interruptions logged yet" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var statusSymbol: String {
        if detector.errorText != nil { return "exclamationmark.triangle" }
        if !cameraRequested { return "camera" }
        if !detector.connected { return "camera.aperture" }
        return detector.hasFace ? "eye" : "viewfinder"
    }

    private var statusColor: Color {
        detector.errorText == nil ? .secondary : .red
    }

    private var status: String {
        if detector.errorText != nil { return "Camera unavailable" }
        if detector.stashed { return "Camera window is returning to the screen" }
        if !cameraRequested { return "Camera is off" }
        if !detector.connected { return "Starting camera…" }
        if detector.touching { return "Hand near face" }
        return detector.hasFace ? "Watching privately on this iPhone" : "Looking for a face"
    }

    private enum MobileAppTab { case dashboard, insights, learn }
}

private struct MobileSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var detector: Detector
    @ObservedObject var settings: AppSettings
    @ObservedObject var license: MobileLicenseManager
    @Binding var vibrateEnabled: Bool
    @Binding var voiceEnabled: Bool
    @Binding var blurEnabled: Bool

    var body: some View {
        NavigationStack {
            Form {
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
                    Button("Replay onboarding", systemImage: "arrow.counterclockwise") {
                        UserDefaults.standard.set(0, forKey: "awairaOnboardingVersion")
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(.indigo)
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

private struct TouchBorder: View {
    let level: Int

    var body: some View {
        if level > 0 {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(level >= 3 ? Color.red : Color.orange,
                              lineWidth: level >= 3 ? 10 : 7)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}
