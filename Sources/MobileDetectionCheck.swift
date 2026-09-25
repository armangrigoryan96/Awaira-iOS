import AVFoundation
import SwiftUI
import UIKit

/// The five detection checks, the phone's version of the desktop app's `DetectionCheckStep.swift`.
///
/// They sit at the end of onboarding, just before the cue picker: see yourself found, make the
/// movement on purpose and watch it register, feel and hear the alert, then a summary. Choosing a
/// cue is a blind choice otherwise — nobody has yet seen a hand to face movement register.
///
/// This is the one place the camera is shown back. Nothing these screens see is recorded: the
/// detector runs in `calibrating` mode for the whole of the rest of onboarding, so a rehearsed
/// movement never reaches the day's history and never buzzes the phone.
enum MobileDetectionCheckPage: Int, CaseIterable {
    case camera, movement, alert, linger, summary

    /// 1-based position, for the "2 / 5" counter.
    var number: Int { rawValue + 1 }
}

/// What the person has managed to verify. Owned by the onboarding view so it survives the five
/// step changes.
@MainActor
final class MobileDetectionCheckState: ObservableObject {
    @Published var sawFace = false
    @Published var sawTouch = false
    @Published var playedAlert = false
    @Published var heardSustained = false
}

// MARK: - Step

struct MobileDetectionCheckView: View {
    let page: MobileDetectionCheckPage
    let accent: Color
    @ObservedObject var detector: Detector
    @ObservedObject var state: MobileDetectionCheckState
    /// Jump past the whole block — shown on the first screen only.
    var onSkip: () -> Void

    /// Up for a couple of seconds after the alert fires, so the cue is visible as well as audible:
    /// a phone on silent would otherwise leave the check looking like it did nothing.
    @State private var showBubble = false
    @State private var bubbleTask: Task<Void, Never>?

    /// True while the sustained cue is being held by a live touch rather than by the "Try it"
    /// button. Drives the bubble over the picture and the line under the button.
    @State private var sustainedByHand = false
    @State private var sustainedPreviewTask: Task<Void, Never>?

    var body: some View {
        // The desktop's order, because it is the one that reads: what this screen is, the picture,
        // the control that rehearses it, then the hint that explains what to look for.
        VStack(spacing: 18) {
            header

            if page == .summary {
                summaryCard
            } else {
                preview
            }

            if page == .alert  { hearItButton }
            if page == .linger { lingerControls }

            if page != .summary { hintCard }

            if page == .camera {
                Button(action: onSkip) {
                    Text("Skip")
                        .scaledFont(13)
                        .foregroundStyle(AwairaPalette.onboardingInk.opacity(0.5))
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 24)
        // Each step is its own view, so `onChange` never reports state that was already true when
        // this one was built — a face found during a step transition would otherwise leave the
        // summary claiming the camera was never tested.
        .onAppear {
            if detector.hasFace  { state.sawFace = true }
            if detector.touching { state.sawTouch = true }
            if page == .linger && detector.touchLevel >= 3 { startSustained(fromHand: true) }
        }
        .onChange(of: detector.hasFace) { _, hasFace in
            if hasFace { state.sawFace = true }
        }
        .onChange(of: detector.touching) { _, touching in
            guard touching else { return }
            state.sawTouch = true
            // The linger screen fires the alert too: the short cue arriving first is what makes the
            // sustained one that follows read as a second, different thing.
            if page == .alert || page == .linger { fireAlert() }
        }
        // Mirrors what `Detector` does at level 3 when the cues are live, so the rehearsal is timed
        // exactly like the real thing.
        .onChange(of: detector.touchLevel) { _, level in
            guard page == .linger else { return }
            if level >= 3 { startSustained(fromHand: true) }
            else if level == 0 { stopSustained() }
        }
        .onDisappear {
            bubbleTask?.cancel()
            stopSustained()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            Text("\(page.number) / 5")
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(accent)

            Text(title)
                .scaledFont(27, weight: .bold, design: .rounded)
                .foregroundStyle(AwairaPalette.onboardingBlue)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .scaledFont(15)
                .foregroundStyle(AwairaPalette.onboardingInk.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 480)
    }

    private var title: String {
        switch page {
        case .camera:   return "Let's test detection"
        case .movement: return "Try a hand to face movement"
        case .alert:    return "Test the alert"
        case .linger:   return "Now hold your hand there"
        case .summary:  return "You're ready!"
        }
    }

    private var subtitle: String {
        switch page {
        case .camera:
            return "Awaira watches for hand movements towards your chin, mouth, hair, or nose. This takes a few seconds."
        case .movement:
            return "Now move your hand towards your face, for example to your chin or mouth. Awaira should detect it."
        case .alert:
            return "When a hand to face movement is detected, Awaira can nudge you with a short sound and a buzz."
        case .linger:
            return "The short alert fires the moment your hand arrives. If it stays, a soft tone and a steady buzz fade in and keep going until you lower your hand."
        case .summary:
            return "Here's what's working. Next, pick the cues you want Awaira to use."
        }
    }

    // MARK: Preview

    private var preview: some View {
        ZStack {
            if let error = detector.errorText {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black)
                deniedCard(error)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        // The picture itself is drawn behind this tile by `IPhoneOnboardingView`,
                        // which owns the one preview layer of the flow. What stays here is
                        // everything that has to sit on top of it.
                        Color.clear

                        if let zone = detector.zone,
                           let rect = PreviewGeometry.rect(zone: zone,
                                                           bufferAspect: detector.bufferAspect,
                                                           viewSize: geo.size) {
                            headBox(rect, in: geo.size)
                        }

                        statusBadge.padding(12)
                    }
                    .animation(.easeInOut(duration: 0.15), value: detector.touching)
                }
            }

            if showBubble { bubble }
        }
        .aspectRatio(detector.bufferAspect, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: 340)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Hand the tile's place to the container, which draws the camera there.
        .anchorPreference(key: CameraSlotKey.self, value: .bounds) { [page.rawValue: $0] }
    }

    /// The box around the head, and the flag that marks a caught movement.
    ///
    /// No mirroring is applied here: the detector leaves the buffer unmirrored and mirrors the
    /// coordinates it publishes, so the preview layer is the piece that has to mirror — which is
    /// exactly what `CameraPreviewView` sets it to do. Both then share one space.
    @ViewBuilder
    private func headBox(_ rect: CGRect, in size: CGSize) -> some View {
        let caught = page != .camera && detector.touching
        let color = caught ? Color.red : accent

        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(color, lineWidth: 3)
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)

        if caught {
            Label("Hand to face detected", systemImage: "exclamationmark.circle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(color, in: Capsule())
                // On the top edge of the box, clamped so it cannot ride off the tile.
                .offset(x: min(max(6, rect.minX), max(6, size.width - 190)),
                        y: max(6, rect.minY - 13))
        }
    }

    private var statusBadge: some View {
        let text: String
        let color: Color
        if detector.hasFace {
            text = "Camera active"; color = .green
        } else if detector.connected {
            text = "Looking for you…"; color = .yellow
        } else {
            text = "Starting the camera…"; color = .white.opacity(0.6)
        }
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private var bubble: some View {
        VStack {
            Label("Keep going", systemImage: "speaker.wave.2.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.white, in: Capsule())
                .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
                .padding(.top, 16)
            Spacer()
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func deniedCard(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash.fill")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.7))
            Text("Awaira can't see the camera")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.white.opacity(0.18), in: Capsule())
        }
        .padding(24)
    }

    // MARK: Hint

    private var hintCard: some View {
        let hint: (symbol: String, title: String, body: String)
        switch page {
        case .camera:
            hint = ("hand.raised.fill", "Look at the camera",
                    "Hold the phone comfortably, with your face in the frame.")
        case .movement:
            hint = ("viewfinder", "Make the movement",
                    "The moment your hand reaches your face, the box around your head turns red.")
        case .linger:
            hint = ("hand.raised.fill", "Hold it there a moment",
                    "The tone and the buzz stop on their own the moment your hand comes away. You pick which cues to keep on the next screen, and can change them anytime in Settings.")
        default:
            hint = ("speaker.wave.2.fill", "Listen and feel",
                    "You should hear a short sound and feel a buzz the moment the movement is detected. You can pick which cues to use on the next screen, and change them anytime in Settings.")
        }
        return HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.14))
                Image(systemName: hint.symbol)
                    .scaledFont(18)
                    .foregroundStyle(accent)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(hint.title)
                    .scaledFont(15, weight: .semibold)
                    .foregroundStyle(AwairaPalette.onboardingInk)
                Text(hint.body)
                    .scaledFont(13)
                    .foregroundStyle(AwairaPalette.onboardingInk.opacity(0.55))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: 480)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AwairaPalette.onboardingInk.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AwairaPalette.onboardingInk.opacity(0.1), lineWidth: 1.5)
        )
    }

    // MARK: Alert

    private var hearItButton: some View {
        Button(action: fireAlert) {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .scaledFont(10, weight: .semibold)
                Text("Try it")
                    .scaledFont(13, weight: .semibold)
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(accent.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Fired from the check itself rather than left to the detector: the cues are off while the
    /// rehearsal runs (`calibrating`), and the person has not chosen which of them to keep yet —
    /// that is the very next screen.
    private func fireAlert() {
        TouchSound.play()
        Haptics.startSustained()
        state.playedAlert = true
        withAnimation(.easeOut(duration: 0.2)) { showBubble = true }
        bubbleTask?.cancel()
        bubbleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            Haptics.stopSustained()
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeIn(duration: 0.3)) { showBubble = false }
        }
    }

    // MARK: Linger

    /// The button is the way in for a phone whose camera was declined, or for anyone who would
    /// rather not sit holding a hand to their face: it runs the same pair for three seconds.
    private var lingerControls: some View {
        VStack(spacing: 10) {
            Button {
                if sustainedPreviewTask != nil || sustainedByHand { stopSustained() }
                else { startSustainedPreview() }
            } label: {
                let running = sustainedPreviewTask != nil || sustainedByHand
                HStack(spacing: 6) {
                    Image(systemName: running ? "stop.fill" : "play.fill")
                        .scaledFont(10, weight: .semibold)
                    Text(running ? "Stop" : "Try it")
                        .scaledFont(13, weight: .semibold)
                }
                .foregroundStyle(accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(accent.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)

            Text(sustainedByHand
                 ? "That's it — lower your hand and it stops."
                 : "Hold your hand at your face and give it a few seconds.")
                .scaledFont(12)
                .foregroundStyle(AwairaPalette.onboardingInk.opacity(0.48))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 480)
    }

    /// Both sustained cues at once, because that is what the app does at level 3. They are started
    /// here rather than left to `Detector`: it keeps every cue silent while `calibrating`, and the
    /// person has not chosen which of them to keep yet — that is the very next screen.
    private func startSustained(fromHand: Bool) {
        // A preview started a moment ago must not cut a live linger short three seconds later.
        sustainedPreviewTask?.cancel()
        sustainedPreviewTask = nil
        Haptics.startSustained()
        CalmingTone.startSustained()
        state.heardSustained = true
        if fromHand {
            sustainedByHand = true
            bubbleTask?.cancel()
            withAnimation(.easeOut(duration: 0.25)) { showBubble = true }
        }
    }

    private func startSustainedPreview() {
        startSustained(fromHand: false)
        sustainedPreviewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            stopSustained()
        }
    }

    private func stopSustained() {
        sustainedPreviewTask?.cancel()
        sustainedPreviewTask = nil
        Haptics.stopSustained()
        CalmingTone.stopSustained()
        if sustainedByHand {
            sustainedByHand = false
            withAnimation(.easeIn(duration: 0.3)) { showBubble = false }
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        VStack(spacing: 0) {
            summaryRow("Camera detection", done: "Working correctly", passed: state.sawFace)
            Divider().overlay(AwairaPalette.onboardingInk.opacity(0.08))
            summaryRow("Alert", done: "Playing correctly", passed: state.playedAlert)
            Divider().overlay(AwairaPalette.onboardingInk.opacity(0.08))
            summaryRow("Lingering cue", done: "Holding while your hand stays", passed: state.heardSustained)
            Divider().overlay(AwairaPalette.onboardingInk.opacity(0.08))
            summaryRow("Tracking", done: "Ready to log your progress", passed: state.sawTouch)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .frame(maxWidth: 480)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AwairaPalette.onboardingInk.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AwairaPalette.onboardingInk.opacity(0.1), lineWidth: 1.5)
        )
    }

    /// A check that was not performed stays grey and says so — nothing here blocks continuing, since
    /// a phone whose camera was declined must still be able to finish onboarding.
    private func summaryRow(_ title: String, done: String, passed: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                .scaledFont(22)
                .foregroundStyle(passed ? Color(red: 0.24, green: 0.72, blue: 0.45)
                                        : AwairaPalette.onboardingInk.opacity(0.25))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .scaledFont(15, weight: .semibold)
                    .foregroundStyle(AwairaPalette.onboardingInk.opacity(passed ? 1 : 0.55))
                Text(passed ? done : "Not tested — you can continue anyway")
                    .scaledFont(12)
                    .foregroundStyle(AwairaPalette.onboardingInk.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }
}

// MARK: - Camera preview

/// Where the check currently on screen wants the camera drawn, keyed by `MobileDetectionCheckPage`.
///
/// The preview does not live in the step. A layer per step froze the app on the very first step
/// change: the steps animate, so for 0.35 s the outgoing check was still on screen while the
/// incoming one was already built, and two preview layers claimed the same session at once —
/// attaching the second one blocks the main thread inside AVFoundation until the capture queue,
/// busy with a Vision pass on every frame, lets the session reconfigure. Handing the same view from
/// step to step instead fixed the freeze but drew black, because a preview layer that changes
/// superview stops rendering. So the container keeps one preview for the whole flow and each step
/// only reports the rectangle it should fill.
struct CameraSlotKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Int: Anchor<CGRect>],
                       nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The live camera, for the five checks and nowhere else in the app. Built once by
/// `IPhoneOnboardingView` and positioned from `CameraSlotKey`.
///
/// Mirrored on purpose: the detector leaves the pixels it measures unmirrored and mirrors the
/// coordinates it publishes instead (see `Detector.displayRect`), so the picture has to be the
/// mirrored one for the head box to land on the head. This is the preview connection's own setting
/// and does not touch the detection connection.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection {
            // The app is portrait-locked, and the detector rotates its own buffer to match.
            connection.videoRotationAngle = 90
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
