import AVKit
import OSLog
import UIKit

/// The floating window: a sliver of nothing, as small as iOS will allow.
///
/// It isn't there to be watched — it's there because iOS only permits the camera while some of the
/// app's pixels are on screen — so it shows no video, no numbers and no colour. Nothing is drawn in
/// it at all: it is transparent in every state, and the reactions to a hand reaching your face are
/// the ones that don't need the window (the buzz, the tone) plus the red frame and blur the app
/// shows when it's open. A bar sitting on top of whatever you're doing, going red, was the cost of
/// the camera staying on; it isn't any more.
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
        view.backgroundColor = .clear
        view.isOpaque = false
        preferredContentSize = PipWindow.preferredSize(thickness: PipWindow.savedThickness)
        // Nothing in the window is meant to be touched: it carries no controls, and a tap that lands
        // on it should not be the app's doing. The window's own drag and close gestures belong to
        // iOS and can't be refused — being a thread narrower than a fingertip is what handles those.
        view.isUserInteractionEnabled = false
    }

    /// A view that says when it has been re-parented. Starting PiP moves our view out of the app and
    /// into the system's window, and that is the moment the black behind it appears — so it is also
    /// the moment worth reacting to. Layout alone was not enough: it runs while the view still sits
    /// in the app, and need not run again once it lands in the window.
    private final class ReparentingView: UIView {
        var onMoveToWindow: (() -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onMoveToWindow?()
        }
    }

    override func loadView() {
        let hosted = ReparentingView()
        hosted.onMoveToWindow = { [weak self] in self?.clearBackdrop() }
        view = hosted
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        clearBackdrop()
        let size = view.bounds.size
        guard size != reportedSize else { return }
        reportedSize = size
        onSizeChange?(size)
    }

    /// Take the black out of whatever AVKit wraps our view in.
    ///
    /// A clear `view` is only clear down to the next opaque thing behind it, and PiP is built for
    /// video, so the containers it hosts us in default to black. This clears every one of them we
    /// can reach — the ancestors, the window, and any sibling sitting behind our view, which is
    /// where a backdrop would live. Anything the system paints in its *own* process is out of reach;
    /// `describeHierarchy()` is what says which of the two we are looking at.
    ///
    /// Called on every layout pass, whenever the view changes window, and again on a few beats after
    /// PiP starts, because the containers are not all in place at the same moment.
    func clearBackdrop() {
        view.backgroundColor = .clear
        view.isOpaque = false
        var child: UIView = view
        var ancestor: UIView? = view.superview
        while let current = ancestor {
            current.backgroundColor = .clear
            current.isOpaque = false
            // A backdrop is a sibling *behind* us, not an ancestor: clearing the container leaves it
            // untouched. Only the ones below our own branch are hidden, so nothing that might be
            // drawing our view is ever removed.
            if let index = current.subviews.firstIndex(of: child) {
                for sibling in current.subviews.prefix(index) {
                    sibling.isHidden = true
                }
            }
            child = current
            ancestor = current.superview
        }
        view.window?.backgroundColor = .clear
        view.window?.isOpaque = false
        // Views were not the whole story: `AVPictureInPicturePlayerLayerView` is a view built around
        // a *layer*, and a layer's background is invisible to the walk above. Clearing the colour is
        // as far as this goes — the layer that carries our pixels to the system's window is
        // somewhere in here, so it is never hidden, never detached, and keeps its contents.
        if let root = view.window?.layer { Self.clearLayerBackgrounds(root) }
    }

    private static func clearLayerBackgrounds(_ layer: CALayer) {
        layer.backgroundColor = nil
        layer.isOpaque = false
        for sublayer in layer.sublayers ?? [] { clearLayerBackgrounds(sublayer) }
    }

    private static func describeLayer(_ layer: CALayer, depth: Int, into lines: inout [String]) {
        let pad = String(repeating: "  ", count: depth)
        let bg = layer.backgroundColor.map { "\($0)" } ?? "nil"
        lines.append("\(pad)\(type(of: layer)) frame=\(layer.frame) opaque=\(layer.isOpaque) hidden=\(layer.isHidden) opacity=\(layer.opacity) contents=\(layer.contents == nil ? "nil" : "set") bg=\(bg)")
        for sublayer in layer.sublayers ?? [] { describeLayer(sublayer, depth: depth + 1, into: &lines) }
    }

    /// One line per view from ours up to the window: who it is, how big, and what it is painting.
    /// The black bar is either something in this list or something in another process, and the two
    /// need completely different answers — so this is the first thing to look at, not a guess.
    func describeHierarchy() -> String {
        var lines: [String] = []
        var node: UIView? = view
        while let current = node {
            let colour = current.backgroundColor.map { "\($0)" } ?? "nil"
            lines.append("""
            \(type(of: current)) frame=\(current.frame) opaque=\(current.isOpaque) \
            alpha=\(current.alpha) bg=\(colour) layerBg=\(String(describing: current.layer.backgroundColor)) \
            subviews=\(current.subviews.map { "\(type(of: $0))" })
            """)
            node = current.superview
        }
        if let window = view.window {
            lines.append("window \(type(of: window)) opaque=\(window.isOpaque) bg=\(window.backgroundColor.map { "\($0)" } ?? "nil") level=\(window.windowLevel.rawValue)")
            lines.append("layers:")
            Self.describeLayer(window.layer, depth: 1, into: &lines)
        } else {
            lines.append("window: none")
        }
        return lines.joined(separator: "\n  ")
    }
}

enum PipWindow {
    /// The two numbers we ask the window to be. They are not a size — AVKit only takes the *ratio*
    /// from them, then picks its own scale (the window comes out the full length of the screen), and
    /// a pinch shrinks it further, which iOS remembers. So the ratio is the only lever on how thin
    /// the thread is: widen it to ask for thinner, and expect a system floor.
    ///
    /// The length is fixed and is only ever the numerator; `thickness` is the number the settings
    /// panel moves. At the default 8 the ratio is 200:1 — up from an early 80:1, because the bar was
    /// still thick enough to grab with a fingertip. Whether asking this thin changed anything is only
    /// answerable on a phone: the HUD prints the size the window actually got (`pip 385×19`).
    ///
    /// The window is invisible now, but its size is still the size of the thing iOS lets the user
    /// drag and tap, so thin is still worth asking for.
    static let length: CGFloat = 1600

    /// How thick to ask for, and the limits of the ask.
    ///
    /// The thin end is where the system floor lives — past some point asking thinner stops changing
    /// anything, which is why the panel shows the height the window actually came out at next to the
    /// value asked for. The thick end is capped rather than open: the window's touches belong to iOS
    /// and cannot be refused, so a bar wide enough to land a finger on is a bar that will get tapped
    /// and dragged. 80 keeps the ratio at 20:1, still unmistakably a bar rather than a rectangle.
    static let defaultThickness: CGFloat = 7
    static let thicknessRange: ClosedRange<CGFloat> = 2...80
    static let thicknessStep: CGFloat = 2

    static func clamp(thickness value: CGFloat) -> CGFloat {
        min(max(value, thicknessRange.lowerBound), thicknessRange.upperBound)
    }

    static func preferredSize(thickness: CGFloat = savedThickness) -> CGSize {
        let t = clamp(thickness: thickness)
        return CGSize(width: t, height: length)
    }

    static func aspectRatio(thickness: CGFloat = savedThickness) -> CGFloat {
        length / clamp(thickness: thickness)
    }

    // MARK: Remembering the choice

    private static let thicknessKey = "pipWindowThickness"

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
}
