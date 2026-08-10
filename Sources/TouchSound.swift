import AudioToolbox

/// A short local cue at the moment a touch is detected. This uses iOS's built-in sound and does
/// not require microphone, notification, or any other permission.
enum TouchSound {
    static func play() {
        // The system's soft "Tock" cue: brief enough to interrupt an automatic movement without
        // becoming distracting. It is intentionally a one-shot, matching desktop Awaira.
        AudioServicesPlaySystemSound(1104)
    }
}
