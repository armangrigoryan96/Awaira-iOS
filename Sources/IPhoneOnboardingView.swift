import SwiftUI

// The iPhone's first run, built from the desktop app's `awaira/frontend/Sources/Onboarding.swift`
// screen for screen: the same paper backdrop, the same animated illustrations, the same copy, the
// same questions, then the five detection checks and a cue picker.
//
// Three desktop steps are deliberately absent. "How did you hear about us?" reports to the server
// on the Mac and the phone has no such call, so here it would only ask a question nobody could ever
// read. The daily-commitment step has nothing to drive on a phone that keeps no streak. Pricing is
// kept out of the learning flow itself; after the profile screen, the access gate offers the
// seven-day free trial before any paid plan.

// MARK: - Model

/// One educational screen: copy + which animated illustration to show + its accent hue.
private struct OnboardingPage: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let cta: String
    let accent: Color
    let illustration: Illustration

    enum Illustration { case awareness, experience, normalTouches, privacy }
}

private let pages: [OnboardingPage] = [
    .init(
        title: "Notice a moment sooner.",
        body: "Awaira notices hand to face movements while you work. It cannot tell why a movement happened or label it — it simply offers an optional moment of awareness.",
        cta: "Show me how it works",
        accent: Color(red: 0.49, green: 0.56, blue: 1.0),
        illustration: .awareness
    ),
    .init(
        title: "Here's what happens, step by step.",
        body: "Reading on your phone, you reach up. Awaira notices. A gentle cue arrives — not a blocker, not an alarm. You lower your hand and carry on. That's it.",
        cta: "I'm ready",
        accent: Color(red: 0.38, green: 0.78, blue: 0.95),
        illustration: .experience
    ),
    .init(
        title: "A movement is just a movement.",
        body: "Many hand to face movements are ordinary: thinking, resting your chin, scratching an itch, or adjusting glasses. A cue is only an invitation to notice — never a judgement or a health conclusion.",
        cta: "Got it",
        accent: Color(red: 0.95, green: 0.65, blue: 0.35),
        illustration: .normalTouches
    ),
    // The desktop's privacy page, with the one sentence the phone has to add: the checks a few
    // screens later ask iOS for the camera, and a promise made here that the flow then breaks is
    // worse than no promise at all. What has not changed is the part that matters — nothing leaves
    // the phone.
    .init(
        title: "Privacy isn't a feature here — it's the whole design.",
        body: "Your camera is analyzed entirely on your iPhone. Camera video, camera images, detections, selected behavior, and progress history are not uploaded. Awaira even works without an internet connection — detection runs fully offline.\n\nIn a moment Awaira will ask for the camera, so you can watch detection work before you decide anything.",
        cta: "Start protecting myself",
        accent: Color(red: 0.42, green: 0.66, blue: 1.0),
        illustration: .privacy
    ),
]

// MARK: - Questions

/// One onboarding question. Answers are stored in @AppStorage under `storageKey`: single-choice as
/// the chosen option id, multi-choice as comma-joined ids — the same keys and the same stable ids
/// the Mac writes, so the two apps record an answer identically.
private struct Question: Identifiable {
    let id = UUID()
    let storageKey: String
    let title: String
    let helper: String
    let footer: String?
    let accent: Color
    let multi: Bool
    let options: [Option]

    struct Option: Identifiable {
        let id: String      // stable key persisted to storage (not the label)
        let label: String
    }
}

private let questions: [Question] = [
    .init(
        storageKey: "behaviors",
        title: "What would you like to notice?",
        helper: "Choose any movement areas that feel useful to reflect on. Awaira notices hand to face motion, not a behaviour or diagnosis.",
        footer: nil,
        accent: Color(red: 0.49, green: 0.56, blue: 1.0),
        multi: true,
        options: [
            .init(id: "hair_pulling",  label: "Movement toward hair"),
            .init(id: "nail_biting",   label: "Movement toward nails"),
            .init(id: "skin_picking",  label: "Movement toward face or skin"),
            .init(id: "face_touching", label: "General hand to face awareness"),
        ]
    ),
    .init(
        storageKey: "frequencyEstimate",
        title: "What's your best guess?",
        helper: "How many times a day does this roughly happen? Don't overthink it.",
        footer: nil,
        accent: Color(red: 0.30, green: 0.82, blue: 0.86),
        multi: false,
        options: [
            .init(id: "few",     label: "A few times"),
            .init(id: "10-30",   label: "Around 10–30"),
            .init(id: "30-100",  label: "Around 30–100"),
            .init(id: "100+",    label: "More than 100"),
            .init(id: "unknown", label: "I honestly don't know"),
        ]
    ),
    .init(
        storageKey: "contexts",
        title: "When does it happen most?",
        helper: "We'll use this to show when it happens most.",
        footer: nil,
        accent: Color(red: 1.0, green: 0.62, blue: 0.38),
        multi: true,
        options: [
            .init(id: "computer", label: "Working on computer"),
            .init(id: "meetings", label: "During meetings"),
            .init(id: "coding",   label: "While coding"),
            .init(id: "thinking", label: "While thinking"),
            .init(id: "studying", label: "Studying"),
            .init(id: "videos",   label: "Watching videos"),
            .init(id: "reading",  label: "Reading"),
            .init(id: "gaming",   label: "Gaming"),
            .init(id: "stress",   label: "During stress"),
            .init(id: "boredom",  label: "During boredom"),
        ]
    ),
    .init(
        storageKey: "goal",
        title: "What would feel useful?",
        helper: "",
        footer: nil,
        accent: Color(red: 0.75, green: 0.52, blue: 0.98),
        multi: false,
        options: [
            .init(id: "pull_less", label: "Notice patterns"),
            .init(id: "awareness", label: "Take a pause"),
            .init(id: "stop",      label: "Choose a cue"),
            .init(id: "stress",    label: "Keep a private reflection"),
        ]
    ),
]

// MARK: - Steps

private let detectionCheckAccent = Color(red: 0.24, green: 0.52, blue: 0.98)
private let cueChoiceAccent     = Color(red: 0.82, green: 0.52, blue: 0.98)
private let profileAccent       = Color(red: 0.30, green: 0.82, blue: 0.86)

/// One step of the flow. The five checks are separate steps rather than one step with its own
/// internal pager, so the progress dots, the back arrow and the shared CTA keep working through
/// them unchanged.
private enum Step {
    case content(OnboardingPage)
    case question(Question)
    case detectionCheck(MobileDetectionCheckPage)
    case cueChoice
    case profileLoading

    var accent: Color {
        switch self {
        case .content(let p):   return p.accent
        case .question(let q):  return q.accent
        case .detectionCheck:   return detectionCheckAccent
        case .cueChoice:        return cueChoiceAccent
        case .profileLoading:   return profileAccent
        }
    }

    var cta: String {
        switch self {
        case .content(let p):   return p.cta
        case .question:         return "Continue"
        case .detectionCheck:   return "Next"
        case .cueChoice:        return "Next"
        case .profileLoading:   return ""   // the step draws its own button
        }
    }
}

private let steps: [Step] = pages.map(Step.content) + questions.map(Step.question)
    + MobileDetectionCheckPage.allCases.map(Step.detectionCheck)
    + [.cueChoice, .profileLoading]

/// Index of the cue picker — where "Skip" on the first check lands.
private let cueChoiceIndex: Int = steps.firstIndex {
    if case .cueChoice = $0 { return true }
    return false
} ?? 0

// MARK: - Container

/// First-run intro. Calls `onFinish` when the person reaches the end of the flow.
struct IPhoneOnboardingView: View {
    /// Shared with `ContentView`, so the session the checks start is the one the app goes on using.
    @ObservedObject var detector: Detector
    var onFinish: () -> Void

    @State private var index = 0
    /// +1 when advancing, -1 when going back — drives the slide direction.
    @State private var direction = 1
    /// The answer to every question, seeded from what a previous run stored — a rerun of onboarding
    /// arrives with its old answers ticked rather than blank. The questions write through dynamic
    /// @AppStorage keys the container can't observe, so each step reports its answer back here and
    /// `canAdvance` reads it: Continue is off only while nothing at all is chosen.
    @State private var answers: [String: String] = Dictionary(
        uniqueKeysWithValues: questions.map {
            ($0.storageKey, UserDefaults.standard.string(forKey: $0.storageKey) ?? "")
        })
    /// What the detection checks have verified. Held here because each step view is re-created on
    /// every index change, so the five check screens can't keep it between themselves.
    @StateObject private var checkState = MobileDetectionCheckState()

    private var step: Step { steps[index] }

    var body: some View {
        ZStack {
            OnboardingBackground(accent: step.accent)

            VStack(spacing: 0) {
                topBar

                GeometryReader { geo in
                    ScrollView(.vertical, showsIndicators: false) {
                        // The current step, re-created per index so transitions fire.
                        Group {
                            switch step {
                            case .content(let page):
                                contentView(page)
                            case .question(let question):
                                QuestionStepView(
                                    question: question,
                                    onAnswerChanged: { answers[question.storageKey] = $0 })
                            case .detectionCheck(let page):
                                MobileDetectionCheckView(page: page,
                                                         accent: detectionCheckAccent,
                                                         detector: detector,
                                                         state: checkState,
                                                         onSkip: skipChecks)
                            case .cueChoice:
                                CueChoiceStepView(accent: cueChoiceAccent)
                            case .profileLoading:
                                ProfileLoadingView(accent: profileAccent, onComplete: finish)
                            }
                        }
                        .id(index)
                        .transition(.asymmetric(
                            insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)
                        ))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geo.size.height)
                        .padding(.vertical, 8)
                    }
                    // The camera, behind the step rather than inside it. One preview layer is built
                    // here and kept for the whole flow — see `CameraSlotKey` for what a layer per
                    // step did to the app — while the checks only say where to put it. Behind, so
                    // the head box and the status badge the step draws stay on top of the picture.
                    .backgroundPreferenceValue(CameraSlotKey.self) { slots in
                        GeometryReader { proxy in
                            let slot = cameraSlot(slots, in: proxy)
                            CameraPreviewView(session: detector.session)
                                .frame(width: max(slot.width, 1), height: max(slot.height, 1))
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .position(x: slot.midX, y: slot.midY)
                                .opacity(slot.isEmpty ? 0 : 1)
                                .allowsHitTesting(false)
                        }
                    }
                }

                if case .profileLoading = step { } else { ctaButton }
            }
            .padding(.top, 14)
            .padding(.bottom, 12)
        }
        .accessibilityIdentifier("iphoneOnboarding")
        // Reaching the checks is what asks iOS for the camera. It stays on — and silent — for the
        // rest of the flow; `finish()` hands it back to the app in its normal, recording mode.
        .onChange(of: index) { _, newIndex in
            guard case .detectionCheck = steps[newIndex] else { return }
            detector.calibrating = true
            detector.start()
        }
        .foregroundStyle(AwairaPalette.onboardingInk)
        // This is a light, paper-like welcome rather than part of the app's dark dashboard. Keeping
        // the first run light also ensures its softened blue type has enough contrast.
        .preferredColorScheme(.light)
    }

    // MARK: Content step — illustration + copy

    private func contentView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)

            illustration(for: page)
                .frame(height: 190)

            VStack(spacing: 14) {
                Text(page.title)
                    .scaledFont(30, weight: .bold, design: .rounded)
                    .foregroundStyle(AwairaPalette.onboardingBlue)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.body)
                    .scaledFont(16, weight: .medium, design: .rounded)
                    .foregroundStyle(AwairaPalette.onboardingInk.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 480)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
    }

    // MARK: Top bar — back arrow + progress dots

    private var topBar: some View {
        ZStack {
            HStack {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .scaledFont(15, weight: .semibold)
                        .foregroundStyle(AwairaPalette.onboardingInk.opacity(0.7))
                        .frame(width: 34, height: 34)
                        .background(AwairaPalette.onboardingInk.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .opacity(index == 0 ? 0 : 1)
                .disabled(index == 0)

                Spacer()
            }

            // Fifteen steps have to fit a phone's width, so the dots are a size down from the Mac's.
            HStack(spacing: 5) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? step.accent : AwairaPalette.onboardingInk.opacity(0.18))
                        .frame(width: i == index ? 20 : 6, height: 6)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: index)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(index + 1) of \(steps.count)")
        }
        .padding(.horizontal, 20)
    }

    private var ctaButton: some View {
        Button(action: next) {
            Text(step.cta)
                .scaledFont(17, weight: .semibold)
                .foregroundStyle(.black.opacity(0.85))
                .frame(maxWidth: 420)
                .padding(.vertical, 16)
                .background(step.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: step.accent.opacity(0.4), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(!canAdvance)
        .opacity(canAdvance ? 1 : 0.5)
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .animation(.easeInOut(duration: 0.3), value: index)
    }

    // MARK: Navigation

    private func next() {
        guard canAdvance else { return }
        if index == steps.count - 1 {
            finish()
            return
        }
        direction = 1
        withAnimation(.easeInOut(duration: 0.35)) { index += 1 }
    }

    private func back() {
        guard index > 0 else { return }
        direction = -1
        withAnimation(.easeInOut(duration: 0.35)) { index -= 1 }
    }

    /// Past the whole block, to the cue picker. For anyone who does not want to rehearse, or whose
    /// phone has no usable camera.
    private func skipChecks() {
        direction = 1
        withAnimation(.easeInOut(duration: 0.35)) { index = cueChoiceIndex }
    }

    /// The rectangle the camera should fill, empty whenever nothing should be shown. Only the step
    /// on screen is consulted: during a transition the one sliding out still reports its own slot,
    /// and both sit in the same place anyway, so the picture never jumps.
    private func cameraSlot(_ slots: [Int: Anchor<CGRect>], in proxy: GeometryProxy) -> CGRect {
        guard case .detectionCheck(let page) = step,
              detector.errorText == nil,
              let anchor = slots[page.rawValue] else { return .zero }
        return proxy[anchor]
    }

    private var canAdvance: Bool {
        switch step {
        case .question(let q):
            // Every question requires at least one selection before continuing.
            return !(answers[q.storageKey] ?? "").isEmpty
        default:
            // A phone without a working camera, or one whose owner declined it, must still be able
            // to finish — so the educational pages, the checks and the cue picker gate nothing.
            return true
        }
    }

    private func finish() {
        // Back to normal: from here detections count and the chosen cues fire.
        detector.calibrating = false
        onFinish()
    }

    @ViewBuilder
    private func illustration(for page: OnboardingPage) -> some View {
        switch page.illustration {
        case .awareness:     AwarenessIllustration(accent: page.accent)
        case .experience:    ExperienceIllustration(accent: page.accent)
        case .normalTouches: NormalTouchesIllustration(accent: page.accent)
        case .privacy:       PrivacyIllustration(accent: page.accent)
        }
    }
}

// MARK: - Question step

/// A question screen: title + helper + a list of selectable options. Writes the answer straight to
/// @AppStorage (single = one id, multi = comma-joined ids).
private struct QuestionStepView: View {
    let question: Question
    /// Reports the answer as it now stands, empty string included: the container gates Continue on it.
    var onAnswerChanged: (String) -> Void = { _ in }
    @AppStorage private var raw: String

    init(question: Question, onAnswerChanged: @escaping (String) -> Void = { _ in }) {
        self.question = question
        self.onAnswerChanged = onAnswerChanged
        self._raw = AppStorage(wrappedValue: "", question.storageKey)
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Text(question.title)
                    .scaledFont(27, weight: .bold, design: .rounded)
                    .foregroundStyle(AwairaPalette.onboardingBlue)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if !question.helper.isEmpty {
                    Text(question.helper)
                        .scaledFont(15)
                        .foregroundStyle(AwairaPalette.onboardingInk.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 480)

            VStack(spacing: 10) {
                ForEach(question.options) { optionRow($0) }
            }

            if let footer = question.footer {
                Text(footer)
                    .scaledFont(14)
                    .foregroundStyle(AwairaPalette.onboardingInk.opacity(0.52))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
                    .padding(.top, 4)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 24)
    }

    private func optionRow(_ opt: Question.Option) -> some View {
        let selected = isSelected(opt.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { toggle(opt.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: question.multi
                      ? (selected ? "checkmark.square.fill" : "square")
                      : (selected ? "largecircle.fill.circle" : "circle"))
                    .scaledFont(18)
                    .foregroundStyle(selected ? question.accent : AwairaPalette.onboardingInk.opacity(0.4))
                Text(opt.label)
                    .scaledFont(16, weight: .medium)
                    .foregroundStyle(AwairaPalette.onboardingInk)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? question.accent.opacity(0.18) : AwairaPalette.onboardingInk.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? question.accent.opacity(0.8) : AwairaPalette.onboardingInk.opacity(0.1),
                            lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Selection state (single = replace, multi = toggle in a comma-joined set)

    private var selectedSet: Set<String> {
        Set(raw.split(separator: ",").map(String.init))
    }

    private func isSelected(_ id: String) -> Bool {
        question.multi ? selectedSet.contains(id) : raw == id
    }

    private func toggle(_ id: String) {
        if question.multi {
            var set = selectedSet
            if set.contains(id) { set.remove(id) } else { set.insert(id) }
            raw = set.sorted().joined(separator: ",")
        } else {
            raw = (raw == id) ? "" : id
        }
        onAnswerChanged(raw)
    }
}

// MARK: - Cue choice step

/// The phone's version of the desktop's reaction picker. The Mac chooses between three screen
/// effects; the phone's three cues are independent of each other — vibrate, tone, dim — so each is
/// a switch with its own live rehearsal rather than one of three alternatives.
private struct CueChoiceStepView: View {
    let accent: Color
    @AppStorage("mobileVibrateEnabled") private var vibrateEnabled = true
    @AppStorage("mobileVoiceEnabled") private var voiceEnabled = false
    @AppStorage("mobileBlurEnabled") private var blurEnabled = true

    /// Which cue is previewing right now, so its button can say "Stop" and the dim demo can run.
    @State private var previewing: Cue? = nil
    @State private var previewTask: Task<Void, Never>? = nil

    private enum Cue { case vibrate, voice, dim }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Text("Pick your gentle nudge")
                    .scaledFont(27, weight: .bold, design: .rounded)
                    .foregroundStyle(AwairaPalette.onboardingBlue)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("When your hand lingers on your face, Awaira brings you back. Try each one and keep the ones that help. You can change them anytime in Settings.")
                    .scaledFont(15)
                    .foregroundStyle(AwairaPalette.onboardingInk.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 480)

            cueCard(cue: .vibrate,
                    on: $vibrateEnabled,
                    icon: "iphone.radiowaves.left.and.right",
                    title: "Vibrate",
                    subtitle: "A buzz that holds while your hand stays near your face.")

            cueCard(cue: .voice,
                    on: $voiceEnabled,
                    icon: "waveform",
                    title: "Calming tone",
                    subtitle: "The same soft tone the desktop app plays while the hand lingers.",
                    aggressive: true)

            cueCard(cue: .dim,
                    on: $blurEnabled,
                    icon: "rectangle.on.rectangle",
                    title: "Dim the screen",
                    subtitle: "Awaira's screen dims with one encouraging line until you lower your hand.",
                    showsDemo: true)
        }
        .padding(.top, 20)
        .padding(.horizontal, 24)
        .onDisappear { stopPreview() }
    }

    /// A small caution pill marking the more intense cue, so the choice isn't only "which is nicer"
    /// but also "how forceful do I want this to be".
    private var aggressiveBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .scaledFont(9, weight: .semibold)
            Text("More aggressive option")
                .scaledFont(11, weight: .semibold)
        }
        .foregroundStyle(Color.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.orange.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private func cueCard(
        cue: Cue,
        on binding: Binding<Bool>,
        icon: String,
        title: String,
        subtitle: String,
        aggressive: Bool = false,
        /// Only the dim cue has something to show: the other two are felt and heard, not seen.
        showsDemo: Bool = false
    ) -> some View {
        let on = binding.wrappedValue
        let running = previewing == cue
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { binding.wrappedValue.toggle() }
        } label: {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: on ? icon : "bell.slash.fill")
                        .scaledFont(18)
                        .foregroundStyle(on ? accent : AwairaPalette.onboardingInk.opacity(0.35))
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .scaledFont(15, weight: .medium)
                            .foregroundStyle(AwairaPalette.onboardingInk)
                        Text(subtitle)
                            .scaledFont(12)
                            .foregroundStyle(AwairaPalette.onboardingInk.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)

                        // The rehearsal button lives inside the label so the card still toggles on
                        // its own tap.
                        Button {
                            if running { stopPreview() } else { startPreview(cue) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: running ? "stop.fill" : "play.fill")
                                    .scaledFont(9, weight: .semibold)
                                Text(running ? "Stop" : "Try it")
                                    .scaledFont(12, weight: .semibold)
                            }
                            .foregroundStyle(accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(accent.opacity(0.15), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)

                        if aggressive { aggressiveBadge.padding(.top, 2) }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .scaledFont(20)
                        .foregroundStyle(on ? accent : AwairaPalette.onboardingInk.opacity(0.25))
                }

                if showsDemo { DimDemo(active: running) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: 480)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(on ? accent.opacity(0.14) : AwairaPalette.onboardingInk.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(on ? accent.opacity(0.75) : AwairaPalette.onboardingInk.opacity(0.1), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    /// Runs the real cue for three seconds — the same call the detector makes at level 3 — so what
    /// is rehearsed here is exactly what the phone will do later.
    private func startPreview(_ cue: Cue) {
        stopPreview()
        switch cue {
        case .vibrate: Haptics.startSustained()
        case .voice:   CalmingTone.startSustained()
        case .dim:     break   // the demo tile below the card is the whole rehearsal
        }
        withAnimation(.easeInOut(duration: 0.25)) { previewing = cue }
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            stopPreview()
        }
    }

    private func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        Haptics.stopSustained()
        CalmingTone.stopSustained()
        withAnimation(.easeInOut(duration: 0.25)) { previewing = nil }
    }
}

/// A phone-shaped tile that dims exactly the way `DimOverlay` does, so the dim cue can be seen
/// before it is chosen.
private struct DimDemo: View {
    let active: Bool

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.16))
                        .frame(maxWidth: i == 3 ? 60 : .infinity)
                        .frame(height: 7)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)

            if active {
                Color.black.opacity(0.55)
                Text("You've got this.")
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(.white)
            }
        }
        .frame(height: 96)
        .background(Color(red: 0.10, green: 0.11, blue: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeInOut(duration: 0.3), value: active)
    }
}

// MARK: - Profile loading step

/// The last screen. On the Mac its button opens pricing; here it opens the app, because there is
/// nothing to sell on the phone.
private struct ProfileLoadingView: View {
    let accent: Color
    let onComplete: () -> Void

    private let items = ["Personalizing reminders", "Setting your baseline", "Preparing detection"]

    @State private var revealed = 0       // how many checkmarks are visible
    @State private var showReady = false

    var body: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 0)

            VStack(spacing: 14) {
                Text("Creating your awareness profile…")
                    .scaledFont(24, weight: .bold, design: .rounded)
                    .foregroundStyle(AwairaPalette.onboardingBlue)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(items.indices, id: \.self) { i in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(i < revealed ? accent.opacity(0.2)
                                                       : AwairaPalette.onboardingInk.opacity(0.06))
                                    .frame(width: 28, height: 28)
                                if i < revealed {
                                    Image(systemName: "checkmark")
                                        .scaledFont(12, weight: .bold)
                                        .foregroundStyle(accent)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: revealed)

                            Text(items[i])
                                .scaledFont(16)
                                .foregroundStyle(AwairaPalette.onboardingInk.opacity(i < revealed ? 0.85 : 0.3))
                                .animation(.easeInOut(duration: 0.3), value: revealed)
                        }
                    }
                }
                .frame(maxWidth: 320, alignment: .leading)
            }

            if showReady {
                VStack(spacing: 16) {
                    Text("You're ready.")
                        .scaledFont(21, weight: .bold, design: .rounded)
                        .foregroundStyle(AwairaPalette.onboardingInk)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                    Button(action: onComplete) {
                        Text("Start using Awaira")
                            .scaledFont(17, weight: .semibold)
                            .foregroundStyle(.black.opacity(0.85))
                            .frame(maxWidth: 420)
                            .padding(.vertical, 16)
                            .background(accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: accent.opacity(0.4), radius: 18, y: 8)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .onAppear(perform: runSequence)
    }

    private func runSequence() {
        for i in items.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i + 1) * 0.7) {
                withAnimation { revealed = i + 1 }
            }
        }
        let total = Double(items.count + 1) * 0.7
        DispatchQueue.main.asyncAfter(deadline: .now() + total) {
            withAnimation(.easeInOut(duration: 0.4)) { showReady = true }
        }
    }
}

// MARK: - Background

/// The soft, text-safe paper illustration used exclusively for the first run, copied from the Mac's
/// asset catalogue so the two first runs are the same picture.
private struct OnboardingBackground: View {
    let accent: Color

    var body: some View {
        Image("OnboardingPaper")
            .resizable()
            // Intentionally stretched rather than cropped: its corner shapes and bottom ripple are
            // part of the composition and must stay visible.
            .overlay(accent.opacity(0.025))
            .ignoresSafeArea()
    }
}

// MARK: - Illustration 1: Awareness radar

/// Concentric pings expanding from a watchful eye — noticing the movement in real time.
private struct AwarenessIllustration: View {
    let accent: Color

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxR = min(size.width, size.height) * 0.46

                for i in 0..<3 {
                    let p = ((t * 0.5 + Double(i) / 3).truncatingRemainder(dividingBy: 1))
                    let radius = maxR * p
                    let ring = CGRect(x: c.x - radius, y: c.y - radius,
                                      width: radius * 2, height: radius * 2)
                    ctx.stroke(Path(ellipseIn: ring),
                               with: .color(accent.opacity((1 - p) * 0.6)),
                               lineWidth: 2)
                }

                // Glow behind the eye.
                let gr = maxR * 0.5
                let glow = CGRect(x: c.x - gr, y: c.y - gr, width: gr * 2, height: gr * 2)
                ctx.fill(Path(ellipseIn: glow), with: .color(accent.opacity(0.16)))

                if let eye = ctx.resolveSymbol(id: 0) {
                    ctx.draw(eye, at: c)
                }
            } symbols: {
                Image(systemName: "eye.fill")
                    .scaledFont(42)
                    .foregroundStyle(accent)
                    .tag(0)
            }
        }
    }
}

// MARK: - Illustration 2: Experience flow

/// Four-step looping animation: reading → hand up → gentle cue → hand down.
private struct ExperienceIllustration: View {
    let accent: Color

    private let steps: [(icon: String, label: String)] = [
        ("iphone",             "Reading normally"),
        ("hand.raised.fill",   "Hand reaches face"),
        ("rays",               "Gentle cue arrives"),
        ("hand.thumbsup.fill", "You lower your hand"),
    ]

    var body: some View {
        TimelineView(.animation) { tl in
            let t    = tl.date.timeIntervalSinceReferenceDate
            let step = Int(t / 1.4) % steps.count   // each step ~1.4 s

            HStack(spacing: 0) {
                ForEach(steps.indices, id: \.self) { i in
                    let active = i == step
                    HStack(spacing: 0) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(active ? accent.opacity(0.22) : AwairaPalette.onboardingInk.opacity(0.05))
                                    .frame(width: 46, height: 46)
                                Image(systemName: steps[i].icon)
                                    .scaledFont(active ? 20 : 17, weight: .semibold)
                                    .foregroundStyle(active ? accent : AwairaPalette.onboardingInk.opacity(0.3))
                            }
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: step)

                            Text(steps[i].label)
                                .scaledFont(10, weight: active ? .semibold : .regular)
                                .foregroundStyle(AwairaPalette.onboardingInk.opacity(active ? 0.9 : 0.28))
                                .multilineTextAlignment(.center)
                                .frame(width: 68)
                                .animation(.easeInOut(duration: 0.25), value: step)
                        }

                        if i < steps.count - 1 {
                            Image(systemName: "chevron.right")
                                .scaledFont(10, weight: .semibold)
                                .foregroundStyle(AwairaPalette.onboardingInk.opacity(0.18))
                                .padding(.bottom, 24)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Illustration 3: Normal touches

/// A face outline with several everyday gestures shown around it — thinking, chin rest, glasses,
/// scratch — to illustrate that not every detection is a habit.
private struct NormalTouchesIllustration: View {
    let accent: Color

    // Tighter radii than the Mac's: the same composition has to sit inside a phone's width.
    private let gestures: [(icon: String, label: String, angle: Double, radius: Double)] = [
        ("hand.raised",        "thinking",         -40,  86),
        ("hand.point.up.left", "chin rest",         30,  84),
        ("eyeglasses",         "adjusting glasses",160,  78),
        ("hand.tap",           "scratching",      -140,  80),
    ]

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let faceR: CGFloat = 30

            // Face circle
            let faceRect = CGRect(x: c.x - faceR, y: c.y - faceR, width: faceR * 2, height: faceR * 2)
            ctx.stroke(Path(ellipseIn: faceRect), with: .color(AwairaPalette.onboardingInk.opacity(0.5)), lineWidth: 2)

            // Eyes
            for dx in [-faceR * 0.36, faceR * 0.36] {
                let eye = CGRect(x: c.x + dx - 3, y: c.y - faceR * 0.2 - 3, width: 6, height: 6)
                ctx.fill(Path(ellipseIn: eye), with: .color(AwairaPalette.onboardingInk.opacity(0.5)))
            }

            // Dashed lines from face to each gesture
            for g in gestures {
                let rad = g.angle * .pi / 180
                let end = CGPoint(x: c.x + cos(rad) * g.radius * 0.62,
                                  y: c.y + sin(rad) * g.radius * 0.62)
                var line = Path(); line.move(to: c); line.addLine(to: end)
                ctx.stroke(line, with: .color(AwairaPalette.onboardingInk.opacity(0.1)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
        }
        .overlay {
            GeometryReader { geo in
                let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ForEach(gestures, id: \.label) { g in
                    let rad = g.angle * .pi / 180
                    let pos = CGPoint(x: c.x + cos(rad) * g.radius,
                                      y: c.y + sin(rad) * g.radius)
                    VStack(spacing: 4) {
                        Image(systemName: g.icon)
                            .scaledFont(17, weight: .medium)
                            .foregroundStyle(accent.opacity(0.75))
                        Text(g.label)
                            .scaledFont(10)
                            .foregroundStyle(AwairaPalette.onboardingInk.opacity(0.45))
                            .fixedSize()
                    }
                    .position(pos)
                }
            }
        }
    }
}

// MARK: - Illustration 4: Privacy

/// A shield over an on-device loop (iPhone ↔ camera) with the cloud crossed out.
private struct PrivacyIllustration: View {
    let accent: Color

    var body: some View {
        ZStack {
            // Dashed "stays on your iPhone" boundary.
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 7]))
                .foregroundStyle(AwairaPalette.onboardingInk.opacity(0.18))
                .frame(width: 240, height: 140)

            HStack(spacing: 28) {
                deviceIcon("iphone", label: "Your iPhone")
                Image(systemName: "arrow.left.arrow.right")
                    .scaledFont(17, weight: .semibold)
                    .foregroundStyle(AwairaPalette.onboardingInk.opacity(0.4))
                deviceIcon("camera.fill", label: "Camera")
            }

            // Shield badge floating at the top.
            Image(systemName: "lock.shield.fill")
                .scaledFont(46)
                .symbolRenderingMode(.palette)
                .foregroundStyle(AwairaPalette.onboardingInk, accent)
                .background(
                    Circle().fill(AwairaPalette.onboardingCanvas).frame(width: 52, height: 52)
                )
                .offset(y: -80)

            // Nothing leaves — cloud crossed out.
            HStack(spacing: 6) {
                Image(systemName: "icloud.slash")
                    .scaledFont(14, weight: .semibold)
                Text("Local detection")
                    .scaledFont(12, weight: .medium)
            }
            .foregroundStyle(AwairaPalette.onboardingInk.opacity(0.55))
            .offset(y: 84)
        }
    }

    private func deviceIcon(_ name: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: name)
                .scaledFont(30)
                .foregroundStyle(accent)
                .frame(width: 52, height: 52)
                .background(AwairaPalette.onboardingInk.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(label)
                .scaledFont(11)
                .foregroundStyle(AwairaPalette.onboardingInk.opacity(0.5))
        }
    }
}
