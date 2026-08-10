import AudioToolbox
import AVFoundation
import CoreHaptics
import Foundation
import UIKit

/// Buzzes the phone for as long as the hand stays on the face, and stops the moment it comes down.
/// Only used while minimized into the floating window, where the app can't blur anything.
///
/// The buzz has to behave like the blur does on the Mac: on while the hand is there, off when it
/// isn't — one unbroken thing, not a rhythm. Only Core Haptics can produce that: a single
/// `hapticContinuous` event, looped. `AudioServicesPlaySystemSound` cannot — it plays one fixed short
/// pulse and ignores further calls until that pulse finishes, so re-triggering it *always* reads as
/// flickering no matter how fast the timer runs.
///
/// The catch is that iOS stops a haptic engine for a backgrounded app, and in the floating window the
/// app is technically backgrounded. Two things give it a chance anyway: the `audio` background mode
/// with an active mixing audio session, and `playsHapticsOnly = false`, which keeps the engine in that
/// audio context instead of a haptics-only one. If the system takes the engine away regardless, it
/// tells us (`stoppedHandler`) and the pulse train takes over — worse, but never silence.
@MainActor
final class Buzzer {

    static let shared = Buzzer()

    /// How often the system vibration is re-triggered while a hand stays on the face. A single pulse
    /// runs for roughly 0.4 s, so re-firing well inside that keeps the motor from stopping between
    /// pulses; at 0.15 s each pulse lands while the previous one is still running, which is as close
    /// to continuous as a backgrounded app can get. Lower is smoother and costs more battery — and
    /// this only runs while a hand is actually on the face, so the cost is bounded.
    static let pulseEvery: TimeInterval = 0.15

    private var timer: Timer?
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var isRunning = false

    /// Start buzzing, or keep buzzing. Safe to call on every frame.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        if startContinuous() { return }
        startPulseTrain()
    }

    /// Stop buzzing. Safe to call when it isn't running.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        engine?.stop()
    }

    /// One continuous haptic event on a loop — an actual unbroken buzz.
    private func startContinuous() -> Bool {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
        do {
            if engine == nil {
                let engine = try CHHapticEngine()
                // Not haptics-only: this keeps the engine attached to the audio context the app
                // already keeps alive for the floating window, which is what might let it survive
                // being backgrounded. The pattern has no audio events, so nothing is heard.
                engine.playsHapticsOnly = false
                engine.isAutoShutdownEnabled = false
                // Whenever the system takes the engine away — which is what it does to backgrounded
                // apps — degrade to the pulse train instead of going quiet.
                engine.stoppedHandler = { [weak self] _ in
                    Task { @MainActor in self?.continuousStopped() }
                }
                engine.resetHandler = { [weak self] in
                    Task { @MainActor in self?.continuousStopped() }
                }
                self.engine = engine
            }
            guard let engine else { return false }
            // Mixing playback, already active for PiP — re-asserting it costs nothing and never
            // interrupts what the user is listening to.
            try? AVAudioSession.sharedInstance().setActive(true)
            try engine.start()

            // 30 s is the longest a single continuous event may run; looping it means the only seam
            // is once every 30 s of an unbroken hand-on-face.
            let event = CHHapticEvent(eventType: .hapticContinuous,
                                      parameters: [
                                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                                      ],
                                      relativeTime: 0, duration: 30)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            try player.start(atTime: CHHapticTimeImmediate)
            self.player = player
            return true
        } catch {
            return false
        }
    }

    /// The system pulled the engine. If the hand is still on the face, keep buzzing the only other way
    /// there is.
    private func continuousStopped() {
        player = nil
        guard isRunning, timer == nil else { return }
        startPulseTrain()
    }

    /// The fallback: re-trigger the system vibration faster than one pulse lasts. Audibly a rhythm
    /// rather than a buzz, which is exactly why it's second choice.
    private func startPulseTrain() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        let timer = Timer(timeInterval: Self.pulseEvery, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

/// Start/stop from the capture queue, where the detection levels come from.
enum Haptics {
    /// A hand has been on the face for the set delay (`AppSettings.buzzAfter`) and is still there.
    nonisolated static func startSustained() {
        Task { @MainActor in Buzzer.shared.start() }
    }

    /// The hand came down — or detection stopped, so we can't know that it hasn't.
    nonisolated static func stopSustained() {
        Task { @MainActor in Buzzer.shared.stop() }
    }
}
