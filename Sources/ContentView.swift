import SwiftUI

struct ContentView: View {
    @StateObject private var detector = Detector()
    @StateObject private var settings = AppSettings()
    /// The settings panel is folded away by default. The camera is used only for on-device
    /// detection; its picture is deliberately never shown in the app.
    @State private var showSettings = false
    /// The camera is deliberately opt-in. First launch shows a privacy-first onboarding flow, and
    /// arriving here still does not trigger iOS's permission sheet until this is set by the user.
    @State private var cameraRequested = false
    @State private var selectedTab: MobileAppTab = .dashboard

    /// UI tests run without a camera (the simulator has none), so they launch with `-UITest` and
    /// the session is never started — the HUD and overlays still render.
    private var isUITest: Bool { ProcessInfo.processInfo.arguments.contains("-UITest") }

    var body: some View {
        ZStack {
            trackingBackground

            // PiP needs a source view in the hierarchy, but this app intentionally never displays
            // the front-camera image. The view remains practically transparent solely as the
            // system source for the blank PiP helper window.
            CameraDisplayView(display: detector.display, showsVideo: false)
                .ignoresSafeArea()
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if selectedTab == .dashboard {
                hud
            } else {
                MobileLearnLibrary()
            }

            if selectedTab == .dashboard && !cameraRequested && !isUITest {
                cameraStartCard
            }
            DimOverlay(active: detector.touchLevel >= 3)
            TouchBorder(level: detector.touchLevel)
        }
        .statusBarHidden()
        .safeAreaInset(edge: .bottom, spacing: 0) { mobileTabBar }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            applyTiming()
        }
        // The setting is live: moving the slider mid-touch changes when this touch escalates,
        // because `DetectionCore` compares the elapsed time against the current config every frame.
        .onChange(of: settings.buzzAfter) { applyTiming() }
        .onChange(of: detector.touchLevel) { level in
            // Desktop Awaira makes one gentle sound at the start of a touch. This is local iOS
            // system audio, so it needs no permission and never records anything.
            if level == 1 { TouchSound.play() }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var mobileTabBar: some View {
        HStack(spacing: 0) {
            mobileTabButton(.dashboard, title: "Dashboard", icon: "chart.bar.fill")
            mobileTabButton(.learn, title: "Learn", icon: "book.closed.fill")
        }
        .padding(.top, 9)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.10)).frame(height: 1) }
    }

    private func mobileTabButton(_ tab: MobileAppTab, title: String, icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(title).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(selectedTab == tab ? Color.mint : .white.opacity(0.56))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }

    private var trackingBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.025, green: 0.06, blue: 0.09),
                     Color(red: 0.04, green: 0.12, blue: 0.14),
                     Color(red: 0.015, green: 0.03, blue: 0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(alignment: .center) {
            Image(systemName: detector.connected ? "eye.slash.fill" : "camera.fill")
                .font(.system(size: 82, weight: .thin))
                .foregroundStyle(.white.opacity(0.06))
                .accessibilityHidden(true)
        }
    }

    private func applyTiming() {
        detector.level3After = settings.buzzAfter
        detector.level2After = settings.lingerAfter
    }

    private var cameraStartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Camera is off", systemImage: "camera.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text("When you are ready, Awaira can use the front camera to notice hand-to-face movement. Camera frames stay on this iPhone and are never recorded or uploaded.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            Button(action: startCamera) {
                Label("Start camera", systemImage: "play.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(22)
        .frame(maxWidth: 360)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .padding(24)
        .accessibilityIdentifier("cameraStartCard")
    }

    private func startCamera() {
        cameraRequested = true
        applyTiming()
        detector.start()
    }

    private var hud: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                dashboardHeader

                if let errorText = detector.errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
                }

                todaySummary
                metricGrid
                weeklyOverview
                activitySummary
                privacySummary
                settingsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .foregroundStyle(.white)
        .shadow(radius: 4)
    }

    private var dashboardHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .accessibilityIdentifier("statusLine")
            }
            Spacer()
            Image(systemName: detector.connected ? "checkmark.shield.fill" : "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(detector.connected ? .mint : .white.opacity(0.55))
                .padding(10)
                .background(.white.opacity(0.08), in: Circle())
        }
    }

    private var todaySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                    Text("\(detector.count)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .accessibilityIdentifier("todayCount")
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("interruptions")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                    Text(String(format: "%.1f / hour", todayRate))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.mint)
                }
            }
            Text(todayInsight)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.68))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.mint.opacity(0.22), lineWidth: 1) }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            metricCard(icon: "checkmark.shield.fill", value: "\(detector.preventedPulls)", label: "stopped early", tint: .mint,
                       note: detector.count > 0 ? "\(preventedPercent)% of today’s interruptions" : "Your early releases appear here")
            metricCard(icon: "hand.raised.fill", value: "\(detector.actualPulls)", label: "lingered contacts", tint: .orange,
                       note: "Reached the feedback delay")
            metricCard(icon: "clock.fill", value: trackedTime, label: "time tracked", tint: .cyan,
                       note: "Camera processing stays on-device")
            metricCard(icon: "calendar", value: "\(detector.weeklyTotal)", label: "last 7 days", tint: .purple,
                       note: weeklyTrendText)
        }
    }

    private func metricCard(icon: String, value: String, label: String, tint: Color, note: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.15), in: Circle())
            Text(value)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
            Text(note)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 144, alignment: .topLeading)
        .padding(14)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1) }
    }

    private var weeklyOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weekly overview")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.1f / hour", detector.weeklyRate))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.mint)
            }
            MobileWeekChart(days: detector.week)
                .frame(height: 125)
            Text("Each bar is a day’s hand-to-face interruptions. Stats remain only on this iPhone.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.50))
        }
        .padding(16)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1) }
    }

    private var activitySummary: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title3)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 3) {
                Text("Recent activity")
                    .font(.subheadline.weight(.semibold))
                Text(lastActivityText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
            }
            Spacer()
        }
        .padding(15)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var privacySummary: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Private by design")
                    .font(.subheadline.weight(.semibold))
                Text("Camera frames are processed live on this iPhone. Awaira does not record or upload video, images, or your detection history.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .background(.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private var preventedPercent: Int {
        guard detector.count > 0 else { return 0 }
        return Int((Double(detector.preventedPulls) / Double(detector.count) * 100).rounded())
    }

    private var trackedTime: String {
        let total = Int(detector.activeSecondsToday.rounded())
        if total < 60 { return "< 1 min" }
        if total < 3600 { return "\(total / 60) min" }
        return String(format: "%dh %02dm", total / 3600, (total % 3600) / 60)
    }

    private var weeklyTrendText: String {
        guard let improvement = detector.weeklyImprovement, abs(improvement) >= 1 else {
            return "Your rolling weekly total"
        }
        let percent = Int(abs(improvement).rounded())
        return improvement > 0 ? "\(percent)% lower than the prior week" : "\(percent)% higher than the prior week"
    }

    private var todayInsight: String {
        guard detector.count > 0 else { return "Your activity and weekly trend will build here as you track." }
        guard detector.preventedPulls > 0 else { return "You are building awareness—every detected moment is useful data." }
        return "You released \(detector.preventedPulls) hand-to-face moment\(detector.preventedPulls == 1 ? "" : "s") before the feedback delay."
    }

    private var lastActivityText: String {
        guard let date = detector.lastDetection else { return "No interruptions logged yet." }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last interruption \(formatter.localizedString(for: date, relativeTo: Date()))."
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(spacing: 12) {
            if showSettings { settingsPanel }
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showSettings.toggle() }
            } label: {
                Label(showSettings ? "done" : "settings",
                      systemImage: showSettings ? "chevron.down" : "slider.horizontal.3")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityIdentifier("settingsToggle")
        }
        .padding(.bottom, 24)
    }

    private var settingsPanel: some View {
        VStack(spacing: 18) {
            orientationPicker
            barThicknessSlider
            buzzDelaySlider
            Button {
                // The app root observes this versioned key and returns to the full onboarding
                // without deleting the user's stats, settings, or read articles.
                UserDefaults.standard.set(0, forKey: "awairaOnboardingVersion")
            } label: {
                Label("Replay onboarding", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.mint)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// How the floating thread lies — the whole of what the app can decide about the window. Which
    /// side of the screen it lands on is iOS's, remembered per orientation and not askable for, so
    /// there are two buttons here rather than four with two that do nothing.
    private var orientationPicker: some View {
        settingRow("floating bar", value: nil) {
            Picker("floating bar", selection: $detector.pipOrientation) {
                Text("horizontal").tag(PipWindow.Orientation.horizontal)
                Text("vertical").tag(PipWindow.Orientation.vertical)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("orientationPicker")
        }
    }

    /// How thick the floating bar is. What travels to AVKit is only the ratio against
    /// `PipWindow.length`, and AVKit picks its own scale from there — so the number on the slider is
    /// an ask, not a measurement. The measurement is next to it: the height the window actually came
    /// out at last time it was up, which is also where the system's floor becomes visible (keep
    /// asking thinner and at some point it stops moving).
    private var barThicknessSlider: some View {
        settingRow("bar thickness", value: thicknessValueLabel) {
            Slider(value: $detector.pipThickness,
                   in: PipWindow.thicknessRange,
                   step: PipWindow.thicknessStep)
                .tint(.green)
                .accessibilityIdentifier("barThicknessSlider")
        }
    }

    private var thicknessValueLabel: String {
        let asked = String(format: "%.0f", detector.pipThickness)
        // The bar's short side, whichever way it's lying.
        guard let size = detector.pipWindowSize else { return asked }
        return asked + String(format: " → %.0f pt", min(size.width, size.height))
    }

    /// How long a hand may stay on the face before the app reacts — the blur while it's open, the
    /// buzz while it's minimized.
    private var buzzDelaySlider: some View {
        settingRow("buzz after", value: String(format: "%.1f s", settings.buzzAfter)) {
            Slider(value: $settings.buzzAfter,
                   in: AppSettings.buzzAfterRange,
                   step: AppSettings.buzzAfterStep)
                .tint(.red)
                .accessibilityIdentifier("buzzDelaySlider")
        }
    }

    private func settingRow<Control: View>(_ title: String,
                                           value: String?,
                                           @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if let value {
                    Text(value)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            control()
        }
    }

    private var status: String {
        if detector.errorText != nil { return "camera unavailable" }
        // A flash, normally: the window is pulled straight back out of the screen edge, because
        // stashed there iOS won't allow the camera to run at all.
        if detector.stashed         { return "window went into the edge — pulling it back out" }
        if !cameraRequested         { return "camera is off" }
        if !detector.connected      { return "starting the camera…" }
        if detector.touching        { return "hand on face — level \(detector.touchLevel)" }
        // iOS only lets the camera run while the app is visible, so leaving the app has to mean
        // shrinking into the floating window rather than closing it.
        return detector.hasFace ? "watching privately on this iPhone"
                                : "looking for a face"
    }
}

private enum MobileAppTab { case dashboard, learn }

/// The desktop app uses a warm red-orange screen edge on contact. On iPhone it is drawn inside
/// Awaira's own window; iOS does not permit an app to draw over other apps.
private struct TouchBorder: View {
    let level: Int

    var body: some View {
        if level > 0 {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(level >= 3 ? Color.red : Color(red: 1, green: 0.34, blue: 0.18),
                              lineWidth: level >= 3 ? 10 : 7)
                .shadow(color: .red.opacity(level >= 3 ? 0.9 : 0.55), radius: 20)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}
