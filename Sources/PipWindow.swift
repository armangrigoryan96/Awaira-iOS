import AVKit
import UIKit

/// The floating window: a bar of colour, as small as iOS will allow.
///
/// It isn't there to be watched — it's there because iOS only permits the camera while some of the
/// app's pixels are on screen — so it shows no video and no numbers. But it is the only surface the
/// app has while you're in another app, so it carries the reaction the open app shows as a red frame:
/// black while nothing is happening, red the moment a hand reaches your face, bright red once it has
/// stayed for the delay set in the settings panel — three seconds unless changed, which is also
/// when the phone starts buzzing.
///
/// Why this is a view controller rather than the sample-buffer window it used to be: with a
/// sample-buffer content source, the window's proportions do not follow the frames we enqueue —
/// feeding it a 240×30 strip still produced a tall portrait window the size of the layer. Video-call
/// PiP is the one place AVKit takes a size *from us*, via `preferredContentSize`.
final class PipWindowController: AVPictureInPictureVideoCallViewController {

    /// The size the system actually settled on, reported whenever it changes. The points we ask for
    /// are only a ratio, so this is the one way to see how tall the bar really is — and where AVKit's
    /// floor sits. `CameraDisplay` forwards it to the HUD, because logs off the device need root.
    var onSizeChange: ((CGSize) -> Void)?
    private var reportedSize: CGSize = .zero

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = PipWindow.colour(for: .idle)
        preferredContentSize = PipWindow.preferredSize(for: PipWindow.savedOrientation,
                                                       thickness: PipWindow.savedThickness)
        // Nothing in the window is meant to be touched: it carries no controls, and a tap that lands
        // on it should not be the app's doing. The window's own drag and close gestures belong to
        // iOS and can't be refused — being a thread narrower than a fingertip is what handles those.
        view.isUserInteractionEnabled = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size != reportedSize else { return }
        reportedSize = size
        onSizeChange?(size)
    }
}

enum PipWindow {
    /// Which way the thread lies. This is the whole of what the app can decide about the floating
    /// window's shape and place.
    ///
    /// Not for lack of trying: pointing PiP at a source view parked against the left edge, then the
    /// right, was tested on a phone and changed nothing — the window returned to wherever it had
    /// last been dragged. iOS keeps one remembered position per orientation and exposes no API for
    /// it, so "put it on the right" is not something a third-party app can ask for. Standing the
    /// thread up or laying it flat is.
    enum Orientation: String, CaseIterable, Identifiable {
        case horizontal, vertical
        var id: String { rawValue }
    }

    /// The two numbers we ask the window to be. They are not a size — AVKit only takes the *ratio*
    /// from them, then picks its own scale (the window comes out the full length of the screen), and
    /// a pinch shrinks it further, which iOS remembers. So the ratio is the only lever on how thin
    /// the thread is: widen it to ask for thinner, and expect a system floor.
    ///
    /// The length is fixed and is only ever the numerator; `thickness` is the number the settings
    /// panel moves. At the default 8 the ratio is 200:1 — up from an early 80:1, because the bar was
    /// still thick enough to grab with a fingertip. Whether asking this thin changed anything is only
    /// answerable on a phone: the HUD prints the size the window actually got (`pip 385×19`).
    static let length: CGFloat = 1600

    /// How thick to ask for, and the limits of the ask.
    ///
    /// The thin end is where the system floor lives — past some point asking thinner stops changing
    /// anything, which is why the panel shows the height the window actually came out at next to the
    /// value asked for. The thick end is capped rather than open: the window's touches belong to iOS
    /// and cannot be refused, so a bar wide enough to land a finger on is a bar that will get tapped
    /// and dragged. 80 keeps the ratio at 20:1, still unmistakably a bar rather than a rectangle.
    static let defaultThickness: CGFloat = 8
    static let thicknessRange: ClosedRange<CGFloat> = 2...80
    static let thicknessStep: CGFloat = 2

    static func clamp(thickness value: CGFloat) -> CGFloat {
        min(max(value, thicknessRange.lowerBound), thicknessRange.upperBound)
    }

    static func preferredSize(for orientation: Orientation,
                              thickness: CGFloat = savedThickness) -> CGSize {
        let t = clamp(thickness: thickness)
        switch orientation {
        case .horizontal: return CGSize(width: length, height: t)
        case .vertical:   return CGSize(width: t, height: length)
        }
    }

    static func aspectRatio(thickness: CGFloat = savedThickness) -> CGFloat {
        length / clamp(thickness: thickness)
    }

    // MARK: Remembering the choice

    private static let orientationKey = "pipWindowOrientation"
    private static let thicknessKey = "pipWindowThickness"

    /// The orientation the user last chose. A floating window that reset itself on every launch
    /// would be worse than not offering the choice.
    static var savedOrientation: Orientation {
        get {
            let raw = UserDefaults.standard.string(forKey: orientationKey) ?? ""
            return Orientation(rawValue: raw) ?? .horizontal
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: orientationKey) }
    }

    /// The thickness the user last chose, same reasoning. `object(forKey:)` because a missing key
    /// reads as 0 through `double(forKey:)`, which is indistinguishable from a real setting.
    static var savedThickness: CGFloat {
        get {
            guard let stored = UserDefaults.standard.object(forKey: thicknessKey) as? Double else {
                return defaultThickness
            }
            return clamp(thickness: CGFloat(stored))
        }
        set { UserDefaults.standard.set(Double(clamp(thickness: newValue)), forKey: thicknessKey) }
    }

    /// What the bar is saying, derived from `DetectionCore`'s levels: 0 away, 1 touching,
    /// 2 lingering, 3 sustained.
    enum Tint: Equatable { case idle, touching, sustained }

    static func tint(forLevel level: Int) -> Tint {
        switch level {
        case ..<1: return .idle
        case 3...: return .sustained
        default:   return .touching
        }
    }

    static func colour(for tint: Tint) -> UIColor {
        switch tint {
        // Black so the window disappears into a dark wallpaper when there's nothing to report.
        case .idle:      return .black
        case .touching:  return UIColor(red: 0.65, green: 0.05, blue: 0.05, alpha: 1)
        case .sustained: return UIColor(red: 1.00, green: 0.15, blue: 0.15, alpha: 1)
        }
    }
}
