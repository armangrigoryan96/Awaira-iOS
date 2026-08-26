import CoreGraphics
import Foundation

/// Where on the head a fingertip landed.
enum FaceZone: String {
    case outside, topofhead, hair, forehead, eye, nose, mouth, chin, cheek, temple, ear, neck
}

/// A classified touch: the zone, which side of the face it is on, and which fingertip did it.
struct ZoneHit: Equatable {
    let zone: FaceZone
    /// "left", "right", or empty for the zones that have no side.
    let side: String
    let fingertipIndex: Int

    /// Label-friendly name, e.g. "cheek-left" — the key the day's zone tally is stored under and
    /// the key `TouchZonesCard`'s anchors are looked up by.
    var name: String { side.isEmpty ? zone.rawValue : "\(zone.rawValue)-\(side)" }
}

/// A coordinate system anchored to the face itself, built from the eye centres, the nose tip and
/// the mouth corners.
///
///     origin = midpoint between the eyes
///     +u     = along the eye line          (so head roll cancels out)
///     +v     = perpendicular, towards the mouth
///     unit   = interocular distance        (so camera distance cancels out)
///
/// This is the whole point of using landmarks rather than the face box: an axis-aligned rectangle
/// cannot tell a cheek from a temple once the head tilts, but (u, v) can, because the axes tilt
/// with the head.
///
/// Vertical thresholds are expressed in fractions of the measured eye→mouth distance rather than
/// fixed anatomical constants, so they adapt to the individual face and to head pitch.
///
/// Copied verbatim from the Mac app's `awaira/frontend/Sources/FaceFrame.swift`, which is itself
/// ported from the Windows app's `Detection/FaceFrame.cs`. Both platforms run Apple's Vision, so
/// every threshold below applies unchanged here — including the crown, whose value exists precisely
/// because of how Vision scales a face. Keep the two files identical: `ParityTests` checks the
/// numbers, and a divergence that is not deliberate is a bug on one of the two platforms.
///
/// Ported from the Windows app's `Detection/FaceFrame.cs` (commit HTF-99), whose thresholds were
/// calibrated against a live camera and a bench of 16 measured touches. The numbers below are that
/// calibrated set — they differ from the older, rounder ones quoted in `informations/TO_MAC.md`,
/// and the code is what was measured.
///
/// One threshold is deliberately *not* the Windows value: the crown, at -1.58 instead of -1.70.
/// Vision's landmarks put a face on a slightly shorter vertical scale than YuNet's five points, so
/// every `vn` here comes out about 7% smaller and the ported constant landed above the top of the
/// head. See the comment on that branch for the measurement. If another threshold ever turns out to
/// be unreachable in the same way, this is the reason to look at first.
struct FaceFrame {
    let origin: CGPoint          // px, in display frame coordinates
    let ex: CGVector             // unit vector along the eye line
    let ey: CGVector             // unit vector towards the mouth
    let ipd: CGFloat             // interocular distance, px
    let mouthV: CGFloat          // v of the mouth corners, in ipd units (~1.1–1.3)

    /// Build from the landmarks of one face.
    ///
    /// Works in pixels, not normalized units: in 0..1 space a 4:3 frame skews every angle, so a
    /// tilted head would be measured against a stretched grid.
    init?(leftEye: CGPoint, rightEye: CGPoint, noseTip: CGPoint,
          mouthLeft: CGPoint, mouthRight: CGPoint) {
        let dx = leftEye.x - rightEye.x, dy = leftEye.y - rightEye.y
        let ipd = (dx * dx + dy * dy).squareRoot()
        guard ipd >= 4 else { return nil }   // face too small / degenerate to reason about

        let origin = CGPoint(x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2)
        let ex = CGVector(dx: dx / ipd, dy: dy / ipd)

        // Perpendicular to the eye line, then turned towards the nose so +v always points down the
        // face — whichever way the head is rolled, and whichever eye the detector labelled which.
        var ey = CGVector(dx: -ex.dy, dy: ex.dx)
        let nx = noseTip.x - origin.x, ny = noseTip.y - origin.y
        if nx * ey.dx + ny * ey.dy < 0 { ey = CGVector(dx: -ey.dx, dy: -ey.dy) }

        // Eye→mouth distance sets the vertical scale of this particular face.
        var mouthV: CGFloat = 0
        for corner in [mouthLeft, mouthRight] {
            let mx = corner.x - origin.x, my = corner.y - origin.y
            mouthV += (mx * ey.dx + my * ey.dy) / ipd
        }
        mouthV /= 2
        guard mouthV >= 0.4 else { return nil }   // nonsense geometry (extreme angle / bad detect)

        self.origin = origin
        self.ex = ex
        self.ey = ey
        self.ipd = ipd
        self.mouthV = mouthV
    }

    /// Frame pixel → (u, v), both in interocular-distance units.
    func project(_ point: CGPoint) -> (u: CGFloat, v: CGFloat) {
        let dx = point.x - origin.x, dy = point.y - origin.y
        return ((dx * ex.dx + dy * ex.dy) / ipd, (dx * ey.dx + dy * ey.dy) / ipd)
    }

    /// Classify a point on the head.
    ///
    /// Vertical bands are fractions of the eye→mouth distance (`vn`: 0 = eye line, 1 = mouth);
    /// horizontal bands are in interocular units.
    func classify(_ point: CGPoint, fingertipIndex: Int) -> ZoneHit {
        let (u, v) = project(point)
        let vn = v / mouthV
        let au = abs(u)

        // Half-width of the central column of zones (forehead · eye · nose · mouth · chin), in
        // interocular units. A face is not a rectangle: it is widest at the brow line and narrows
        // towards the chin, so a single constant could not fit both ends. At 0.62 everywhere, the
        // outer corner of the eye (0.68 on the head artwork) and the outer end of the eyebrow
        // (~0.70) fell outside it and were filed as "cheek" — which is how cheek became the bucket
        // that caught everything. Widening it everywhere instead swallowed the corner of the mouth,
        // where real cheek touches sit at 0.71.
        let half = 0.78 + (0.62 - 0.78) * min(max((vn + 0.6) / 1.1, 0), 1)

        var zone: FaceZone
        var side = ""
        let screenDx = point.x - origin.x

        if au > 1.7 || vn > 2.6 {
            zone = vn > 2.0 ? .neck : .outside
        } else if vn < -1.58 {
            // -1.58, where Windows uses -1.70, because Vision's landmarks put the same head on a
            // slightly shorter scale than YuNet's five points do. Measured on the shared head
            // artwork: Windows read the crown at vn -1.76, Vision reads it at -1.636 (mouthV 1.065
            // against YuNet's 1.1-1.3, so every vn comes out about 7% smaller). Ported literally,
            // -1.70 sat *above* the apex and the zone was unreachable — crown touches were all
            // filed as hair, which is exactly what the first run showed.
            //
            // -1.58 keeps Windows' own margin: 0.06 of vn below the apex, enough for a curled
            // fingertip resting on the crown. The bench's hairline touches (-1.2 and -1.58 on
            // YuNet's scale, so about -1.12 and -1.47 here) stay comfortably on the hair side.
            zone = .topofhead
        } else if vn < -1.15 {
            zone = .hair                        // hairline and above, before the crown
            side = Self.side(screenDx)
        } else if au > 0.90, vn > -0.2, vn < 0.9 {
            // 0.90, not the 1.15 this started at: on the artwork the ear's front edge is at 0.85
            // and its outer rim at 1.24, so 1.15 handed the front two thirds of the ear to "cheek".
            // The vertical window is what separates the ear from the temple in front of it.
            zone = .ear
            side = Self.side(screenDx)
        } else if au > half {
            zone = vn < -0.35 ? .temple : .cheek
            side = Self.side(screenDx)
        } else {
            switch vn {
            case ..<(-0.35): zone = .forehead
            case ..<0.35:    zone = .eye
            case ..<0.80:    zone = .nose
            case ..<1.25:    zone = .mouth
            case ..<2.00:    zone = .chin
            default:         zone = .neck
            }
            if zone == .eye { side = Self.side(screenDx) }
        }

        return ZoneHit(zone: zone, side: side, fingertipIndex: fingertipIndex)
    }

    /// The side is named the way the person feels it: touching your own right cheek is filed as
    /// "right", so the head artwork reads like a mirror and the number lights up on the right.
    ///
    /// Confirmed at the camera, not derived: reading the code alone suggested the opposite sign,
    /// because `Detector` mirrors x exactly once (`displayRect` and `handPoints` both map
    /// `x → 1 - x`), which should have put the person's right side on the right of the display. It
    /// does not — the camera hands over an already-mirrored selfie image, so that single flip
    /// cancels it out and screen-left is the person's right. The Windows app landed on the same
    /// inverted sign for the same reason.
    ///
    /// If this ever has to be re-checked: touch your own right cheek and watch the head artwork.
    /// The number must appear on the right.
    private static func side(_ dx: CGFloat) -> String { dx < 0 ? "right" : "left" }
}
