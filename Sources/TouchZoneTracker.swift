import CoreGraphics
import Foundation

/// Names *where* on the head a touch landed — cheek, temple, forehead, hair… — using the face
/// landmarks via `FaceFrame`.
///
/// Deliberately a separate type rather than a branch inside `Detector`: the state machine that
/// decides *whether* a touch is happening (debounce, escalation levels) must keep behaving exactly
/// as it did. This one only observes — it reads the zone the detector already settled on and adds a
/// label, which the dashboard counts up. **Nothing here can start, extend or suppress a touch.**
///
/// Copied verbatim from the Mac app's `awaira/frontend/Sources/TouchZoneTracker.swift` (which was
/// ported from the Windows app's `Detection/TouchZoneTracker.cs`). Pure geometry — no camera, no
/// Vision — so it runs on the phone as it stands; keep the two files identical.
///
/// On the phone it lives on `Detector`'s capture queue, alongside `MobileStatsStore`, and is touched
/// from nowhere else.
final class TouchZoneTracker {
    /// Fingertip landmark indices in priority order — an index finger resting near the face should
    /// win over a pinky that happens to be a few pixels closer.
    private static let fingertips = [8, 4, 12, 16, 20]

    /// A zone has to repeat before it is reported, so a fingertip skimming past the mouth on its
    /// way to the chin does not show up as a mouth touch. Independent of the detector's own
    /// minFrames/releaseFrames — this cannot influence whether a touch counts.
    private static let confirmFrames = 2

    /// Face detection only runs every Nth frame, so the frame from the last face pass is held and
    /// reused in between; it is dropped as soon as the head zone itself goes away.
    private var face: FaceFrame?

    private var candidate: ZoneHit?
    private var streak = 0

    // How many frames the touch in progress has spent in each zone, and the running leader. A
    // finger wanders (cheek → temple → hair), so the touch is filed under wherever it dwelled
    // longest rather than wherever it first landed.
    private var dwell: [String: Int] = [:]
    private var dominant: ZoneHit?
    private var dominantFrames = 0
    private var wasTouching = false

    /// The confirmed zone of the touch in progress, or nil when nothing is being touched.
    ///
    /// Nothing reads this yet — the Today page shows the day's totals, not a live label. It is the
    /// reason the two-frame gate exists (a label that flickers between cheek and temple is worse
    /// than none), and it is kept so a live readout can be added without re-deriving the gate. The
    /// stored totals do not depend on it: those come from the dwell vote below.
    private(set) var current: ZoneHit?

    /// Where the touch that just ended spent most of its frames. Read on the falling edge; nil if
    /// the touch was never classified (hand inside the head box but off the head, or the face lost
    /// for its whole duration), so the caller can tell "nowhere" from "the zone before".
    private(set) var lastCompleted: ZoneHit?

    /// Call once per frame, after the detector's own processing.
    ///
    /// - Parameters:
    ///   - faceFrame: a freshly built frame on face passes, nil on the frames in between.
    ///   - faceChecked: whether this frame ran the face request at all.
    ///   - hands: hand landmarks in normalized display coordinates.
    ///   - zone: the detector's head zone, or nil when there is no head.
    ///   - touching: the detector's own touch state.
    ///   - frameSize: pixel size of the frame the landmarks came from.
    /// - Returns: the zone of the touch that just *ended* on this frame, if one did.
    @discardableResult
    func update(faceFrame: FaceFrame?, faceChecked: Bool,
                hands: [[CGPoint]], zone: [Double]?, touching: Bool,
                frameSize: CGSize) -> ZoneHit? {
        // The dwell tally closes on the detector's touch, not on this class's own hits: a fingertip
        // that dips out of the zone for a frame does not end the touch as far as the app is
        // concerned, so it must not close the tally either.
        var completed: ZoneHit?
        if wasTouching, !touching { completed = commitTouch() }
        wasTouching = touching

        if faceChecked, let faceFrame { face = faceFrame }

        // No head zone means no head to classify against, so the held face frame is stale too.
        guard let zone else {
            face = nil
            reset()
            return completed
        }
        guard let face else {
            reset()
            return completed
        }

        guard let hit = findTouch(hands: hands, zone: zone, face: face, frameSize: frameSize) else {
            reset()
            return completed
        }

        if let prev = candidate, prev.zone == hit.zone, prev.side == hit.side {
            streak += 1
        } else {
            candidate = hit
            streak = 1
        }
        if streak >= Self.confirmFrames { current = candidate }

        // Every classified frame votes, confirmed or not. The two-frame gate exists so the *live
        // label* does not flicker; the tally is already a vote across the whole touch and smooths
        // itself. When the vote was gated too, a short touch whose zone wobbled — or that lost the
        // hand for a single frame, which resets the streak — finished with an empty tally: the
        // day's counter went up and nothing on the head did.
        if touching { tally(hit) }

        return completed
    }

    private func reset() {
        candidate = nil
        streak = 0
        current = nil
    }

    /// Add a frame to the zone's dwell count and keep the running leader.
    private func tally(_ hit: ZoneHit) {
        let frames = (dwell[hit.name] ?? 0) + 1
        dwell[hit.name] = frames
        if frames > dominantFrames {
            dominantFrames = frames
            dominant = hit
        }
    }

    /// Close the tally for a finished touch: publish the longest-held zone and start over.
    private func commitTouch() -> ZoneHit? {
        lastCompleted = dominant
        let result = dominant
        dwell.removeAll()
        dominant = nil
        dominantFrames = 0
        return result
    }

    /// Two-stage: the normalized head zone is the gate, then the pixel-space face frame says which
    /// part of the head it was.
    private func findTouch(hands: [[CGPoint]], zone: [Double], face: FaceFrame,
                           frameSize: CGSize) -> ZoneHit? {
        guard zone.count == 4 else { return nil }
        for index in Self.fingertips {
            for hand in hands where index < hand.count {
                let p = hand[index]
                if p.x < 0 { continue }                                   // (-1,-1) — missing joint
                if p.x < zone[0] || p.x > zone[2] || p.y < zone[1] || p.y > zone[3] { continue }

                let pixel = CGPoint(x: p.x * frameSize.width, y: p.y * frameSize.height)
                let hit = face.classify(pixel, fingertipIndex: index)
                if hit.zone == .outside { continue }         // inside the box, off the head
                return hit
            }
        }
        return nil
    }
}
