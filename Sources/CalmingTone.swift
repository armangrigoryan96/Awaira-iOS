import AVFoundation

/// The iPhone version of the desktop's calming tone: a soft, looping two-sine drone played while a
/// hand lingers on the face, if the user has switched the "voice" cue on. Off by default.
///
/// Same synthesis as the Mac's `CalmingAudio` (441 Hz + 447 Hz, quiet), but it sets a mixing
/// playback session so it layers over whatever the person is listening to and keeps sounding while
/// Awaira is minimized into the floating window (the app declares the `audio` background mode).
@MainActor
final class MobileCalmingAudio {

    static let shared = MobileCalmingAudio()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var active = false
    private var built = false

    private func build() {
        guard !built else { return }
        built = true
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        engine.mainMixerNode.outputVolume = 0.5
    }

    func start() {
        guard !active else { return }
        active = true
        build()
        guard let buffer = makeBuffer() else { active = false; return }
        // Mixing playback so the tone layers over music and survives the floating-window background.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        do {
            try engine.start()
        } catch {
            active = false
            return
        }
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
    }

    func stop() {
        guard active else { return }
        active = false
        player.stop()
        engine.stop()
    }

    /// Two detuned sine waves (441 Hz + 447 Hz) at low amplitude; 441 divides 44100 cleanly so the
    /// one-second buffer loops without a click.
    private func makeBuffer() -> AVAudioPCMBuffer? {
        let sampleRate: Double = 44100
        let frameCount = AVAudioFrameCount(sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let ch = buffer.floatChannelData else { return nil }
        buffer.frameLength = frameCount

        let f1: Double = 441.0
        let f2: Double = 447.0
        let amp: Float = 0.14

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let s = Float(sin(2 * .pi * f1 * t) + sin(2 * .pi * f2 * t)) * amp * 0.5
            ch[0][i] = s
            ch[1][i] = s
        }
        return buffer
    }
}

/// Start/stop the calming tone from anywhere, hopping to the main actor like `Haptics` does.
enum CalmingTone {
    nonisolated static func startSustained() {
        Task { @MainActor in MobileCalmingAudio.shared.start() }
    }
    nonisolated static func stopSustained() {
        Task { @MainActor in MobileCalmingAudio.shared.stop() }
    }
}
