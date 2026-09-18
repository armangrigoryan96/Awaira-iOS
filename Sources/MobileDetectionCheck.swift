import AVFoundation
import SwiftUI
import UIKit

/// The four detection checks, the phone's version of the desktop app's `DetectionCheckStep.swift`.
///
/// They sit at the end of onboarding, just before the cue picker: see yourself found, make the
/// movement on purpose and watch it register, feel and hear the alert, then a summary. Choosing a
/// cue is a blind choice otherwise — nobody has yet seen a hand-to-face movement register.
///
/// This is the one place the camera is shown back. Nothing these screens see is recorded: the
/// detector runs in `calibrating` mode for the whole of the rest of onboarding, so a rehearsed
/// movement never reaches the day's history and never buzzes the phone.
enum MobileDetectionCheckPage: Int, CaseIterable {
    case camera, movement, alert, summary

    /// 1-based position, for the "2 / 4" counter.
    var number: Int { rawValue + 1 }
}

/// What the person has managed to verify. Owned by the onboarding view so it survives the four
/// step changes.
@MainActor
final class MobileDetectionCheckState: ObservableObject {
    @Published var sawFace = false
    @Published var sawTouch = false
    @Published var playedAlert = false
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if page == .summary {
                summaryCard
            } else {
                preview
                hintCard
            }

            if page == .alert { hearItButton }

            if page == .camera {
                Button("Skip", action: onSkip)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
        }
        .padding(.top, 24)
        .onChange(of: detector.hasFace) { _, hasFace in
            if hasFace { state.sawFace = true }
        }
        .onChange(of: detector.touching) { _, touching in
            guard touching else { return }
            state.sawTouch = true
            if page == .alert { fireAlert() }
        }
        .onDisappear { bubbleTask?.cancel() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(page.number) / 4")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)

            Text(title)
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
    }

    private var title: String {
        switch page {
        case .camera:   return "Let's test detection"
        case .movement: return "Try a hand-to-face movement"
        case .alert:    return "Test the alert"
        case .summary:  return "You're ready!"
        }
    }

    private var subtitle: String {
        switch page {
        case .camera:
            return "Awaira watches for hand movements towards your face — chin, mouth, hair, nose. This takes a few seconds."
        case .movement:
            return "Now move your hand towards your face — touch your chin or mouth, for example. Awaira should detect it."
        case .alert:
            return "When a hand-to-face movement is detected, Awaira can nudge you with a short sound and a buzz."
        case .summary:
            return "Here's what's working. Next, pick the cues you want Awaira to use."
        }
    }

    // MARK: Preview

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black)

            if let error = detector.errorText {
                deniedCard(error)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        CameraPreviewView(session: detector.session)

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
            Label("Hand-to-face detected", systemImage: "exclamationmark.circle.fill")
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
            Label("Hey, keep going 💙", systemImage: "speaker.wave.2.fill")
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
        default:
            hint = ("speaker.wave.2.fill", "Listen and feel",
                    "You should hear a short sound and feel a buzz the moment the movement is detected. You can pick which cues to use on the next screen, and change them anytime in Settings.")
        }
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: hint.symbol)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 38, height: 38)
                .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(hint.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(hint.body).font(.footnote).foregroundStyle(.secondary).lineSpacing(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color(uiColor: .separator), lineWidth: 1) }
    }

    // MARK: Alert

    private var hearItButton: some View {
        Button(action: fireAlert) {
            Label("Try it", systemImage: "play.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(accent.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
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

    // MARK: Summary

    private var summaryCard: some View {
        VStack(spacing: 0) {
            summaryRow("Camera detection", done: "Working correctly", passed: state.sawFace)
            Divider().padding(.leading, 38)
            summaryRow("Alert", done: "Playing correctly", passed: state.playedAlert)
            Divider().padding(.leading, 38)
            summaryRow("Tracking", done: "Ready to log your progress", passed: state.sawTouch)
        }
        .padding(.horizontal, 16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color(uiColor: .separator), lineWidth: 1) }
    }

    /// A check that was not performed stays grey and says so — nothing here blocks continuing, since
    /// a phone whose camera was declined must still be able to finish onboarding.
    private func summaryRow(_ title: String, done: String, passed: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(passed ? .green : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(passed ? .primary : .secondary)
                Text(passed ? done : "Not tested — you can continue anyway")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }
}

// MARK: - Camera preview

/// The live camera, for the four checks and nowhere else in the app.
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
