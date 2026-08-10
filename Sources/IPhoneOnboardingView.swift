import SwiftUI

/// The iPhone version of Awaira's desktop onboarding. It keeps the same education and reflective
/// questions, but it never asks iOS for a permission: camera access remains a separate, explicit
/// choice on the main screen after this flow ends.
struct IPhoneOnboardingView: View {
    var onFinish: () -> Void

    @State private var index = 0
    @State private var source = ""
    @State private var otherSource = ""
    @State private var answers: [String: Set<String>] = [:]

    private var step: OnboardingStep { onboardingSteps[index] }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.035, green: 0.075, blue: 0.105)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

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
                        .fill(stepIndex == index ? step.accent : .white.opacity(0.16))
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
        case .acquisition: acquisitionPage
        case .question(let question): questionPage(question)
        case .nudge: nudgePage
        }
    }

    private func educationPage(_ page: EducationPage) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 18)
            Image(systemName: page.symbol)
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(page.accent)
                .frame(width: 128, height: 128)
                .background(page.accent.opacity(0.14), in: Circle())
                .overlay { Circle().stroke(page.accent.opacity(0.34), lineWidth: 1) }
            Text(page.title)
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text(page.body)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .lineSpacing(3)
            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, minHeight: 440)
    }

    private var acquisitionPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("How did you hear about us?", helper: "Choose one option — it helps us understand where people discover Awaira. Your answer stays private.")
            optionGrid(options: ["YouTube", "TikTok", "Instagram", "Google Search", "Facebook", "Reddit", "Other"], selected: source, multiple: false) { choice in
                source = choice
            }
            if source == "Other" {
                TextField("Please specify", text: $otherSource)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.14), lineWidth: 1) }
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, 30)
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
                                .foregroundStyle(selected.contains(option) ? question.accent : .white.opacity(0.42))
                            Text(option)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 15)
                        .background(selected.contains(option) ? question.accent.opacity(0.15) : .white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                        .overlay { RoundedRectangle(cornerRadius: 14).stroke(selected.contains(option) ? question.accent.opacity(0.65) : .white.opacity(0.11), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
            if let footer = question.footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineSpacing(2)
                    .padding(.top, 6)
            }
        }
        .padding(.top, 30)
    }

    private var nudgePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Pick your gentle nudge", helper: "When a hand lingers near your face, Awaira reacts to bring you back. On iPhone, the app shows a visual cue while open and buzzes while it is in the floating window. You can change the timing anytime in Settings.")
            nudgeRow(symbol: "rectangle.on.rectangle", title: "Visual cue while Awaira is open", detail: "The head-zone frame changes colour when a hand reaches your face, then the screen blurs if it stays there.", color: .red)
            nudgeRow(symbol: "iphone.radiowaves.left.and.right", title: "Buzz while Awaira is minimized", detail: "The floating bar changes colour and your iPhone buzzes after the delay you choose.", color: .orange)
            nudgeRow(symbol: "slider.horizontal.3", title: "Change it anytime", detail: "Set the delay, floating-bar orientation, and its thickness from the in-app settings panel.", color: .mint)
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
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 26)
        .background(.black.opacity(0.72))
    }

    private func stepTitle(_ title: String, helper: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if !helper.isEmpty {
                Text(helper)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.66))
                    .lineSpacing(3)
            }
        }
    }

    private func optionGrid(options: [String], selected: String, multiple: Bool, select: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(options, id: \.self) { option in
                Button { select(option) } label: {
                    Text(option)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .padding(.horizontal, 10)
                        .background(selected == option ? step.accent.opacity(0.18) : .white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
                        .overlay { RoundedRectangle(cornerRadius: 13).stroke(selected == option ? step.accent.opacity(0.7) : .white.opacity(0.11), lineWidth: 1) }
                }
                .buttonStyle(.plain)
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
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.white)
                Text(detail).font(.footnote).foregroundStyle(.white.opacity(0.62)).lineSpacing(2)
            }
        }
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
        .overlay { RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.1), lineWidth: 1) }
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
        case .acquisition: return !source.isEmpty && (source != "Other" || !otherSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        case .question(let question): return !(answers[question.key, default: []].isEmpty)
        case .education, .nudge: return true
        }
    }

    private func advance() {
        if index == onboardingSteps.count - 1 { finish() }
        else { withAnimation(.easeInOut(duration: 0.22)) { index += 1 } }
    }

    private func finish() {
        UserDefaults.standard.set(source == "Other" ? otherSource : source, forKey: "onboarding.acquisitionSource")
        for (key, values) in answers { UserDefaults.standard.set(values.sorted().joined(separator: ","), forKey: "onboarding.\(key)") }
        onFinish()
    }
}

private struct OnboardingStep {
    enum Kind { case acquisition, education(EducationPage), question(OnboardingQuestion), nudge }
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
        .init(symbol: "hand.raised.fill", accent: .indigo, title: "You're not doing it on purpose.", body: "Most people with hair pulling, nail biting, or skin picking don't realize they're doing it until after it happens. The behavior is automatic—it slips in while you work, study, read, or watch videos."),
        .init(symbol: "eye.fill", accent: .mint, title: "Awareness changes behavior.", body: "Many habit-reversal approaches start with awareness training: learning to notice the behavior before it runs on autopilot. Awaira is an awareness coach that catches it in real time."),
        .init(symbol: "brain.head.profile", accent: .orange, title: "Your brain is seeking relief.", body: "Hair pulling and nail biting can give a brief feeling of relief from stress, boredom, or tension. That's why stopping feels surprisingly hard. The goal isn't perfection—it's interruption."),
        .init(symbol: "chart.line.uptrend.xyaxis", accent: .green, title: "Small interruptions, big impact.", body: "Habit Reversal Training works by raising awareness and replacing automatic habits with another action. Each catch chips away at the loop. Most people notice dozens of automatic touches on Day 1. That's completely normal. Awareness comes before improvement."),
        .init(symbol: "arrow.uturn.backward.circle.fill", accent: .cyan, title: "Here's what happens, step by step.", body: "You reach up. Awaira notices. A gentle visual cue appears—not a blocker, not an alarm. You lower your hand and carry on."),
        .init(symbol: "hand.point.up.left.fill", accent: .yellow, title: "Not every detection is a habit.", body: "Thinking, resting your chin, scratching an itch, and adjusting glasses are all normal. Awaira notices hand-to-face contact because habits can begin with an ordinary touch. A reminder does not mean you were about to pull—it means Awaira is helping you stay aware."),
        .init(symbol: "lock.shield.fill", accent: .blue, title: "Privacy isn't a feature here—it's the whole design.", body: "Camera frames, detections, selected behavior, and progress history are not uploaded. Detection runs on this iPhone, even without an internet connection. This onboarding will not ask for any permissions.")
    ]
    let questions: [OnboardingQuestion] = [
        .init(key: "behaviors", title: "What behavior do you want to reduce?", helper: "Awaira watches for hand-to-face movements. It may also notice non-habit touches so it can help interrupt the behavior earlier.", footer: nil, options: ["Hair pulling", "Nail biting", "Skin picking (face area)", "Reduce face touching (general awareness)"], multiple: true, accent: .indigo),
        .init(key: "frequencyEstimate", title: "What's your best guess?", helper: "How many times a day does this roughly happen? Don't overthink it.", footer: nil, options: ["A few times", "Around 10–30", "Around 30–100", "More than 100", "I honestly don't know"], multiple: false, accent: .mint),
        .init(key: "contexts", title: "When does it happen most?", helper: "We'll use this to show when you're most vulnerable to automatic habits.", footer: nil, options: ["Working on computer", "During meetings", "While coding", "While thinking", "Studying", "Watching videos", "Reading", "Gaming", "During stress", "During boredom"], multiple: true, accent: .orange),
        .init(key: "lifeImpact", title: "How much does this affect your life?", helper: "", footer: "Most people are surprised by how often these habits happen once they become visible. That's exactly what Awaira is here to help with.", options: ["Rarely bothers me", "Sometimes affects me", "Often affects me", "Has a major impact"], multiple: false, accent: .green),
        .init(key: "goal", title: "What would you like to achieve?", helper: "", footer: nil, options: ["Pull less often", "Become more aware", "Stop completely", "Reduce stress"], multiple: false, accent: .purple)
    ]
    return [.init(kind: .acquisition, accent: .indigo, cta: "Continue")]
        + pages.map { .init(kind: .education($0), accent: $0.accent, cta: $0.title == "You're not doing it on purpose." ? "Yep, that's me" : "Continue") }
        + questions.map { .init(kind: .question($0), accent: $0.accent, cta: "Continue") }
        + [.init(kind: .nudge, accent: .purple, cta: "Continue")]
}()
