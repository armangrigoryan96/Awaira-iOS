import SwiftUI

/// The iPhone version of Awaira's desktop onboarding: the same education and reflective questions,
/// then the four detection checks, then the cue picker.
///
/// The checks are where the camera is first asked for — they cannot show detection working without
/// it. Everything before them still asks for nothing, and the privacy page says so in those words.
struct IPhoneOnboardingView: View {
    /// Shared with `ContentView`, so the session the checks start is the one the app goes on using.
    @ObservedObject var detector: Detector
    var onFinish: () -> Void

    @State private var index = 0
    @StateObject private var checkState = MobileDetectionCheckState()
    @State private var answers: [String: Set<String>] = [:]
    @AppStorage("mobileVibrateEnabled") private var vibrateEnabled = true
    @AppStorage("mobileVoiceEnabled") private var voiceEnabled = false
    @AppStorage("mobileBlurEnabled") private var blurEnabled = true

    private var step: OnboardingStep { onboardingSteps[index] }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    stepContent
                        .frame(maxWidth: 620)
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                        .padding(.bottom, 26)
                }

                footer
            }
        }
        .accessibilityIdentifier("iphoneOnboarding")
        // Replaying onboarding shows the answers already given, as the Mac's does — every question
        // opens on its stored choice, so a second run is an edit rather than a blank form.
        .onAppear(perform: restoreSavedAnswers)
        // Reaching the checks is what asks iOS for the camera. It stays on — and silent — for the
        // rest of the flow; `finish()` hands it back to the app in its normal, recording mode.
        .onChange(of: index) { _, newIndex in
            guard case .detectionCheck = onboardingSteps[newIndex].kind else { return }
            detector.calibrating = true
            detector.start()
        }
    }

    private var header: some View {
        VStack(spacing: 13) {
            HStack {
                Text("Awaira")
                    .font(.headline.weight(.bold))
                Spacer()
            }
            HStack(spacing: 6) {
                ForEach(onboardingSteps.indices, id: \.self) { stepIndex in
                    Capsule()
                        .fill(stepIndex == index ? step.accent : Color.secondary.opacity(0.25))
                        .frame(width: stepIndex == index ? 22 : 5, height: 5)
                        .animation(.easeInOut(duration: 0.2), value: index)
                }
            }
            .accessibilityLabel("Step \(index + 1) of \(onboardingSteps.count)")
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    @ViewBuilder private var stepContent: some View {
        switch step.kind {
        case .education(let page): educationPage(page)
        case .question(let question): questionPage(question)
        case .detectionCheck(let page):
            MobileDetectionCheckView(page: page, accent: step.accent, detector: detector,
                                     state: checkState, onSkip: skipChecks)
        case .nudge: nudgePage
        }
    }

    private func educationPage(_ page: EducationPage) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 18)
            MobileOnboardingIllustration(symbol: page.symbol, accent: page.accent)
                .frame(width: 210, height: 150)
            Text(page.title)
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
            Text(page.body)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, minHeight: 440)
    }

    private func questionPage(_ question: OnboardingQuestion) -> some View {
        let selected = answers[question.key, default: []]
        return VStack(alignment: .leading, spacing: 18) {
            stepTitle(question.title, helper: question.helper)
            VStack(spacing: 10) {
                ForEach(question.options, id: \.self) { option in
                    Button {
                        toggle(option, for: question)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected.contains(option) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(option) ? question.accent : .secondary)
                            Text(option)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 15)
                        .background(selected.contains(option) ? question.accent.opacity(0.12) : Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected.contains(option) ? question.accent.opacity(0.65) : Color(uiColor: .separator), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
            if let footer = question.footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .padding(.top, 6)
            }
        }
        .padding(.top, 30)
    }

    private var nudgePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Choose your cues", helper: "Choose any combination. Awaira only uses the options you check, and you can change them at any time in Settings.")
            nudgeToggle(symbol: "iphone.radiowaves.left.and.right", title: "Vibrate", detail: "Buzz while a hand stays near your face.", color: .orange, isOn: $vibrateEnabled)
            nudgeToggle(symbol: "waveform", title: "Voice", detail: "Play the same soft calming tone used in the desktop app.", color: .purple, isOn: $voiceEnabled)
            nudgeToggle(symbol: "rectangle.on.rectangle", title: "Blur screen", detail: "Dim the screen briefly while Awaira is open.", color: .mint, isOn: $blurEnabled)
        }
        .padding(.top, 30)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button(action: advance) {
                Text(index == onboardingSteps.count - 1 ? "Continue to Awaira" : step.cta)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .tint(step.accent)
            .disabled(!canAdvance)
            .opacity(canAdvance ? 1 : 0.45)

            if index > 0 {
                Button("Back") { withAnimation(.easeInOut(duration: 0.2)) { index -= 1 } }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 26)
        .background(.bar)
    }

    private func stepTitle(_ title: String, helper: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            if !helper.isEmpty {
                Text(helper)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
    }

    private func nudgeRow(symbol: String, title: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(detail).font(.footnote).foregroundStyle(.secondary).lineSpacing(2)
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color(uiColor: .separator), lineWidth: 1) }
    }

    private func nudgeToggle(symbol: String, title: String, detail: String, color: Color,
                             isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(isOn.wrappedValue ? color : .secondary)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(isOn.wrappedValue ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary).lineSpacing(2)
                }
                Spacer(minLength: 8)
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn.wrappedValue ? color : .secondary)
            }
            .padding(16)
            .background(isOn.wrappedValue ? color.opacity(0.10) : Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(isOn.wrappedValue ? color.opacity(0.45) : Color(uiColor: .separator), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ option: String, for question: OnboardingQuestion) {
        var selected = answers[question.key, default: []]
        if question.multiple {
            if selected.contains(option) { selected.remove(option) } else { selected.insert(option) }
        } else {
            selected = [option]
        }
        answers[question.key] = selected
    }

    private var canAdvance: Bool {
        switch step.kind {
        case .question(let question): return !(answers[question.key, default: []].isEmpty)
        // A phone without a working camera, or one whose owner declined it, must still be able to
        // finish onboarding — so the checks gate nothing.
        case .education, .detectionCheck, .nudge: return true
        }
    }

    private func advance() {
        if index == onboardingSteps.count - 1 { finish() }
        else { withAnimation(.easeInOut(duration: 0.22)) { index += 1 } }
    }

    /// Puts the stored answers back on screen. Anything not recognised (an option that has since
    /// been renamed) is dropped rather than shown as a selection the list cannot display.
    private func restoreSavedAnswers() {
        let defaults = UserDefaults.standard
        for step in onboardingSteps {
            guard case .question(let question) = step.kind, answers[question.key] == nil else { continue }
            let stored = (defaults.string(forKey: question.key) ?? "")
                .split(separator: ",")
                .map(String.init)
                .filter(question.options.contains)
            if !stored.isEmpty { answers[question.key] = Set(stored) }
        }
    }

    /// Past the whole block, to the cue picker. For anyone who does not want to rehearse, or whose
    /// phone has no usable camera.
    private func skipChecks() {
        withAnimation(.easeInOut(duration: 0.22)) { index = nudgeStepIndex }
    }

    private func finish() {
        let defaults = UserDefaults.standard
        for (key, values) in answers { defaults.set(values.sorted().joined(separator: ","), forKey: key) }
        // Back to normal: from here detections count and the chosen cues fire.
        detector.calibrating = false
        onFinish()
    }
}

/// The mobile version keeps the desktop onboarding's illustration-first rhythm, scaled for a
/// phone: a moving cue, the focused symbol, and a small sequence of evidence dots.
private struct MobileOnboardingIllustration: View {
    let symbol: String
    let accent: Color

    var body: some View {
        TimelineView(.animation) { context in
            let phase = (sin(context.date.timeIntervalSinceReferenceDate * 1.5) + 1) / 2
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(accent.opacity((0.28 - Double(index) * 0.07) * (0.55 + phase * 0.45)), lineWidth: 1.5)
                        .frame(width: CGFloat(76 + index * 34) + phase * 10,
                               height: CGFloat(76 + index * 34) + phase * 10)
                }
                Image(systemName: symbol)
                    .font(.system(size: 43, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 84, height: 84)
                    .background(accent.opacity(0.15), in: Circle())
                    .overlay { Circle().stroke(accent.opacity(0.5), lineWidth: 1.5) }
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle().fill(index == 2 ? accent : Color.secondary.opacity(0.25)).frame(width: 7, height: 7)
                    }
                }
                .offset(y: 82)
            }
        }
    }
}

private struct OnboardingStep {
    enum Kind {
        case education(EducationPage), question(OnboardingQuestion)
        case detectionCheck(MobileDetectionCheckPage), nudge
    }
    let kind: Kind
    let accent: Color
    let cta: String
}

private struct EducationPage {
    let symbol: String
    let accent: Color
    let title: String
    let body: String
}

private struct OnboardingQuestion {
    let key: String
    let title: String
    let helper: String
    let footer: String?
    let options: [String]
    let multiple: Bool
    let accent: Color
}

private let onboardingSteps: [OnboardingStep] = {
    let pages: [EducationPage] = [
        .init(symbol: "hand.raised.fill", accent: .indigo, title: "Notice a moment sooner.", body: "Awaira notices hand to face movements while you work, study, read, or watch videos. It cannot tell why a movement happened or label it."),
        .init(symbol: "eye.fill", accent: .mint, title: "Optional cues.", body: "A calm cue can make a hand to face movement easier to notice. You choose which cues to use and can change them at any time."),
        .init(symbol: "brain.head.profile", accent: .orange, title: "Awaira doesn't diagnose.", body: "A movement is just a movement. Awaira does not diagnose a condition or decide what you intended to do."),
        .init(symbol: "chart.line.uptrend.xyaxis", accent: .green, title: "Your history stays private.", body: "Your on-device history can help you reflect on the moments you choose to notice. It is not a score or a measure of your health."),
        .init(symbol: "arrow.uturn.backward.circle.fill", accent: .cyan, title: "How it works", body: "When your hand moves toward your face, Awaira shows a short visual cue. Lower your hand and carry on."),
        .init(symbol: "hand.point.up.left.fill", accent: .yellow, title: "Most touches are normal.", body: "Thinking, resting your chin, scratching an itch, and adjusting glasses are all normal. A cue just helps you notice. It isn't a judgement or a health conclusion."),
        // The permission sentence names the camera on purpose: the detection checks a few screens
        // later ask for it, and a promise made here that the flow then breaks is worse than no
        // promise at all. What has not changed is the part that matters — nothing leaves the phone.
        .init(symbol: "lock.shield.fill", accent: .blue, title: "Everything stays on your iPhone.", body: "Camera frames, detections, selected behavior, and progress history are not uploaded. Detection runs on this iPhone, even without an internet connection. In a moment Awaira will ask for the camera, so you can watch detection work before you decide anything.")
    ]
    let questions: [OnboardingQuestion] = [
        .init(key: "behaviors", title: "What would you like to notice?", helper: "Awaira notices hand to face motion, not a behaviour or diagnosis.", footer: nil, options: ["Movement toward hair", "Movement toward nails", "Movement toward face or skin", "General hand to face awareness"], multiple: true, accent: .indigo),
        .init(key: "frequencyEstimate", title: "What's your best guess?", helper: "How many times a day does this roughly happen? Don't overthink it.", footer: nil, options: ["A few times", "Around 10–30", "Around 30–100", "More than 100", "I honestly don't know"], multiple: false, accent: .mint),
        .init(key: "contexts", title: "When does it happen most?", helper: "We'll use this to show when it happens most.", footer: nil, options: ["Working on computer", "During meetings", "While coding", "While thinking", "Studying", "Watching videos", "Reading", "Gaming", "During stress", "During boredom"], multiple: true, accent: .orange),
        .init(key: "goal", title: "What would feel useful?", helper: "", footer: nil, options: ["Notice patterns", "Take a pause", "Choose a cue", "Keep a private reflection"], multiple: false, accent: .purple)
    ]
    // The four checks go last before the cue picker: by then the person knows what Awaira watches
    // for, and the picker stops being a blind choice.
    let checks = MobileDetectionCheckPage.allCases.map {
        OnboardingStep(kind: .detectionCheck($0), accent: .blue, cta: "Continue")
    }
    return pages.map { .init(kind: .education($0), accent: $0.accent, cta: "Continue") }
        + questions.map { .init(kind: .question($0), accent: $0.accent, cta: "Continue") }
        + checks
        + [.init(kind: .nudge, accent: .purple, cta: "Continue")]
}()

/// Index of the cue picker — where "Skip" on the first check lands.
private let nudgeStepIndex: Int = onboardingSteps.firstIndex {
    if case .nudge = $0.kind { return true }
    return false
} ?? 0
