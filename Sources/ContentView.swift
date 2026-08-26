import SwiftUI

/// The app shell: the four tabs of the design, the detection overlays that sit above all of them,
/// and the settings the detector needs applied whenever they change.
///
/// The tab bar is drawn by `MobileTabBar` rather than by `TabView` — the design puts the selected
/// item on a solid blue plate, which `tabItem` cannot do.
struct ContentView: View {
    @StateObject private var detector = Detector()
    @StateObject private var settings = AppSettings()
    @EnvironmentObject private var license: MobileLicenseManager
    @State private var cameraRequested = false
    @State private var selectedTab: MobileAppTab = .today

    @AppStorage("mobileVibrateEnabled") private var vibrateEnabled = true
    @AppStorage("mobileVoiceEnabled") private var voiceEnabled = false
    @AppStorage("mobileBlurEnabled") private var blurEnabled = true
    @AppStorage("mobileAppearance") private var appearance = MobileAppearance.system.rawValue

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MobileTabBar(selection: $selectedTab)
            }
            .background(AwairaPalette.window.ignoresSafeArea())

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
        .preferredColorScheme(MobileAppearance(rawValue: appearance)?.colorScheme)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            // Before the first card is read, so the goal is never shown as the bare default to a
            // user whose onboarding answer implies a different starting point. No-ops after that.
            MobileGoal.seedIfNeeded()
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

    @ViewBuilder private var tabContent: some View {
        switch selectedTab {
        case .today:
            TodayView(detector: detector,
                      cameraRequested: cameraRequested,
                      onToggleCamera: toggleCamera,
                      onOpenSettings: { selectedTab = .settings },
                      onOpenPatterns: { selectedTab = .patterns })
        case .patterns:
            MobilePatternsView(detector: detector)
        case .reflect:
            // The reflection surface itself is still to come; the library is the calmest thing to
            // put here in the meantime, and it keeps the tab from being a dead end.
            MobileLearnLibrary()
        case .settings:
            MobileSettingsView(detector: detector,
                               settings: settings,
                               license: license,
                               vibrateEnabled: $vibrateEnabled,
                               voiceEnabled: $voiceEnabled,
                               blurEnabled: $blurEnabled)
        }
    }

    private var isUITest: Bool { ProcessInfo.processInfo.arguments.contains("-UITest") }

    /// The header pill is the app's only camera switch, so it has to work both ways: the first tap
    /// asks for the camera, every one after that pauses or resumes it.
    ///
    /// Resuming goes through `togglePause`, never `stop()`/`start()` — the capture session's input
    /// is wired once and adding it a second time fails, so a stopped detector cannot be restarted.
    private func toggleCamera() {
        guard !isUITest else { return }
        if cameraRequested {
            detector.togglePause()
        } else {
            cameraRequested = true
            applyTiming()
            detector.start()
        }
    }

    private func applyTiming() {
        detector.level3After = settings.buzzAfter
        detector.level2After = settings.lingerAfter
    }

    private func applyAlerts() {
        detector.vibrateEnabled = vibrateEnabled
        detector.voiceEnabled = voiceEnabled
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
