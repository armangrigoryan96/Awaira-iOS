import SwiftUI

/// The app shell: the three daily destinations, the detection overlays that sit above all of them,
/// and the settings the detector needs applied whenever they change.
///
/// The tab bar is drawn by `MobileTabBar` rather than by `TabView` — the design cuts the selected
/// item out of the bar into the page's own colour, which `tabItem` cannot do.
struct ContentView: View {
    /// Injected by `AwairaApp`, which owns it: onboarding's detection checks run on this same
    /// detector, so the camera session it started is the one this screen carries on with.
    @ObservedObject var detector: Detector
    @StateObject private var settings = AppSettings()
    @StateObject private var journal = JournalStore()
    @StateObject private var premiumStore = PremiumStore()
    /// Detection is the app's primary job, so a completed onboarding starts it immediately.
    /// The header control remains a pause/resume switch for the rare times someone wants it off.
    @State private var cameraRequested = !ProcessInfo.processInfo.arguments.contains("-UITest")
    // Screenshot automation can open any product surface directly without changing normal app
    // launch behavior. This keeps the public-site exports tied to the native SwiftUI screens.
    @State private var selectedTab: MobileAppTab = Self.launchTab
    @State private var showingSettings = false
    @State private var showingPremiumPaywall = ProcessInfo.processInfo.arguments.contains("-ScreenshotPaywall")
    @State private var showingContext = false
    @State private var selectedContext: String?
    @State private var contextNote = ""
    @State private var addingNote = false
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("mobileVibrateEnabled") private var vibrateEnabled = true
    @AppStorage("mobileVoiceEnabled") private var voiceEnabled = false
    @AppStorage("mobileBlurEnabled") private var blurEnabled = true
    // The product's dashboard is designed around a near-black canvas; people can still explicitly
    // choose Light or System in Settings, but a fresh install now opens in the intended treatment.
    @AppStorage("mobileAppearance") private var appearance = MobileAppearance.dark.rawValue

    var body: some View {
        Group {
            if allowsPreviewAccess || premiumStore.isPremiumUnlocked || premiumStore.isFreeTrialActive {
                appShell
            } else {
                PremiumAccessGate(store: premiumStore)
            }
        }
        .preferredColorScheme(MobileAppearance(rawValue: appearance)?.colorScheme)
        .task { await premiumStore.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await premiumStore.refresh() } }
        }
        .onChange(of: premiumStore.isPremiumUnlocked) { _, unlocked in
            unlocked ? activatePremiumCapture() : deactivatePremiumCapture()
        }
        .onChange(of: premiumStore.isFreeTrialActive) { _, active in
            active ? activatePremiumCapture() : deactivatePremiumCapture()
        }
        .sheet(isPresented: $showingSettings) {
            MobileSettingsView(detector: detector, settings: settings, journal: journal,
                               vibrateEnabled: $vibrateEnabled, voiceEnabled: $voiceEnabled,
                               blurEnabled: $blurEnabled, premiumStore: premiumStore)
        }
        .sheet(isPresented: $showingPremiumPaywall) {
            PremiumPaywallView(store: premiumStore)
        }
        .sheet(isPresented: $showingContext) { contextPrompt }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            applyTiming()
            applyAlerts()
            if premiumStore.isPremiumUnlocked || premiumStore.isFreeTrialActive {
                activatePremiumCapture()
            } else {
                // Onboarding may have already created the camera session. Never leave capture
                // running behind the required purchase screen.
                deactivatePremiumCapture()
            }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var allowsPreviewAccess: Bool {
        // Automated screenshots must be able to show ordinary product screens, but production
        // launches always go through the entitlement gate.
        ProcessInfo.processInfo.arguments.contains("-UITest")
    }

    private var appShell: some View {
        ZStack {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AwairaPalette.window.ignoresSafeArea())
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    MobileTabBar(selection: $selectedTab)
                }

            DimOverlay(active: blurEnabled && detector.touchLevel >= 3)
            TouchBorder(level: detector.touchLevel)
        }
        .onChange(of: settings.buzzAfter) { _, _ in applyTiming() }
        .onChange(of: vibrateEnabled) { _, _ in applyAlerts() }
        .onChange(of: voiceEnabled) { _, _ in applyAlerts() }
        .onChange(of: detector.touchLevel) { _, level in
            if level == 1 {
                TouchSound.play()
                // Each new face-touch run can be reflected on. A prompt already on screen remains
                // in control until it is saved or skipped, so one touch never creates duplicates.
                guard !showingContext else { return }
                selectedContext = nil; contextNote = ""; addingNote = false; showingContext = true
            }
        }
    }

    private func activatePremiumCapture() {
        guard !isUITest else { return }
        if detector.isPaused { detector.togglePause() }
        detector.start()
    }

    private func deactivatePremiumCapture() {
        guard !isUITest, !detector.isPaused else { return }
        detector.togglePause()
    }

    @ViewBuilder private var tabContent: some View {
        switch selectedTab {
        case .today:
            TodayView(detector: detector,
                      cameraRequested: cameraRequested,
                      onToggleCamera: toggleCamera,
                      onOpenSettings: { showingSettings = true })
        case .patterns:
            MobileInsightsView(detector: detector, journal: journal,
                               onOpenSettings: { showingSettings = true })
        case .wins:
            MobileAchievementsView(detector: detector,
                                   onOpenSettings: { showingSettings = true })
        case .learn:
            // The reflection surface itself is still to come; the library is the calmest thing to
            // put here in the meantime, and it keeps the tab from being a dead end.
            MobileLearnLibrary()
        case .journal:
            // Without this tab the context prompt still writes entries, to a place nothing in the
            // app can open again.
            MobileJournalView(journal: journal)
        }
    }

    private var isUITest: Bool { ProcessInfo.processInfo.arguments.contains("-UITest") }

    private static var launchTab: MobileAppTab {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ScreenshotPatterns") { return .patterns }
        if arguments.contains("-ScreenshotJournal") { return .journal }
        return .today
    }

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

    /// What Awaira asks the moment a hand reaches the face. Deliberately short: it interrupts
    /// something, so it offers one tap and a way out, and never blocks on being answered.
    ///
    /// It was built from `.bordered`/`.borderedProminent`/`.roundedBorder` controls, which paint
    /// iOS's own tint and chrome straight over the design's palette — the one screen in the app the
    /// user cannot avoid seeing was also the one that looked least like the app.
    private var contextPrompt: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What made you touch your face?")
                    .awairaDisplay(23)
                    .foregroundStyle(AwairaPalette.text)
                Text("Choose what was happening. It stays on this iPhone.")
                    .awairaCaption(14)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.55))
            }
            .padding(.bottom, 16)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                      spacing: 8) {
                ForEach(Self.contextChoices, id: \.self) { item in
                    MobileChip(title: item, isSelected: selectedContext == item) {
                        selectedContext = (selectedContext == item) ? nil : item
                    }
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.16)) { addingNote.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: addingNote ? "checkmark.square.fill" : "square")
                        .scaledFont(14)
                    Text("Add a note")
                        .scaledFont(14, weight: .medium)
                }
                .foregroundStyle(addingNote ? AwairaPalette.accent : AwairaPalette.ink.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(.top, 14)

            if addingNote {
                TextField("Private note", text: $contextNote, axis: .vertical)
                    .scaledFont(14)
                    .foregroundStyle(AwairaPalette.text)
                    .lineLimit(1...3)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(AwairaPalette.window,
                                in: RoundedRectangle(cornerRadius: AwairaPalette.cardRadius,
                                                     style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AwairaPalette.cardRadius, style: .continuous)
                            .strokeBorder(AwairaPalette.cardBorder, lineWidth: 1)
                    )
                    .padding(.top, 9)
            }

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                Button("Skip") { showingContext = false }
                    .buttonStyle(AwairaSecondaryButton())
                Button("Save") {
                    if let selectedContext {
                        journal.add(activity: selectedContext, note: contextNote)
                    }
                    showingContext = false
                }
                .buttonStyle(AwairaPrimaryButton(enabled: selectedContext != nil))
                .disabled(selectedContext == nil)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AwairaPalette.statsSurface.ignoresSafeArea())
        .presentationDetents([.height(addingNote ? 400 : 300)])
        .presentationDragIndicator(.visible)
        .presentationBackground(AwairaPalette.statsSurface)
    }

    private static let contextChoices = ["Thoughts", "Working", "Reading",
                                         "Studying", "Screen time", "Other"]
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
