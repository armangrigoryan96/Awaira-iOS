import Foundation
import QuartzCore

/// Decides how hard to fight a *stashed* Picture-in-Picture window, with no AVKit involved so it
/// can be tested.
///
/// Swiping the floating window into the screen edge stashes it: nothing of the app is on screen
/// any more, so iOS revokes camera access (`videoDeviceNotAvailableInBackground` — the one
/// interruption `isMultitaskingCameraAccessEnabled` does *not* shield us from). The only way to
/// keep detecting is to put the window back.
///
/// The order matters. The cheap attempt is asking PiP to start again on the still-active
/// controller: if that lifts the stash, the size the user pinched the window to survives. Only if
/// that fails do we stop and restart PiP, which works but may reset the window to its default size.
///
/// And we never stop trying. The edge is a place the window can only lose in: stashed, the camera
/// is off, so the app does nothing at all until the user happens to pull it back out. There is
/// nothing to preserve there, so retries keep going for as long as iOS keeps the window in the wall
/// — `softRetryAfter` is what keeps that from becoming a spin.
struct StashPolicy {

    enum Action: Equatable {
        /// Ask the active controller to start PiP again — lifts the stash without touching size.
        case soft
        /// Stop and immediately restart PiP.
        case restart
        /// Too soon after the last attempt to know whether it worked.
        case wait
    }

    /// How long to give an attempt before deciding it didn't lift the stash. Short, because the
    /// camera is off the whole time — but not zero, or the poll would restart PiP on every tick.
    var softRetryAfter: TimeInterval = 0.25

    private var attempts = 0
    private var lastAttemptAt: CFTimeInterval = 0

    /// Call while the window is stashed — on the transition and on every poll after it.
    mutating func actionOnSuspend(at time: CFTimeInterval) -> Action {
        if attempts == 0 {
            attempts = 1
            lastAttemptAt = time
            return .soft
        }
        guard time - lastAttemptAt >= softRetryAfter else { return .wait }
        attempts += 1
        lastAttemptAt = time
        return .restart
    }

    /// The window is back on screen — the next stash starts from the cheap attempt again.
    mutating func reset() {
        attempts = 0
        lastAttemptAt = 0
    }
}
