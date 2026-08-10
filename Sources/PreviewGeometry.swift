import CoreGraphics

/// Maps normalized detection coordinates onto the preview view.
///
/// The preview layer aspect-*fills*, so it crops the camera buffer on one axis. The overlay has
/// to crop the same way or the head-zone box drifts away from the face it's drawn around. Pure
/// math, so it's covered by unit tests rather than by squinting at a phone.
enum PreviewGeometry {

    /// The rect the (aspect-filled) camera buffer occupies in the view's coordinate space.
    /// It is at least as large as the view and overflows on exactly one axis.
    /// - Parameter bufferAspect: buffer width / height, in the same orientation as the view.
    static func filledRect(bufferAspect: CGFloat, viewSize: CGSize) -> CGRect {
        guard bufferAspect > 0, viewSize.width > 0, viewSize.height > 0 else {
            return CGRect(origin: .zero, size: viewSize)
        }
        let viewAspect = viewSize.width / viewSize.height
        if bufferAspect > viewAspect {
            // Buffer is relatively wider → match heights, overflow left and right.
            let width = viewSize.height * bufferAspect
            return CGRect(x: (viewSize.width - width) / 2, y: 0,
                          width: width, height: viewSize.height)
        } else {
            // Buffer is relatively taller → match widths, overflow top and bottom.
            let height = viewSize.width / bufferAspect
            return CGRect(x: 0, y: (viewSize.height - height) / 2,
                          width: viewSize.width, height: height)
        }
    }

    /// A normalized display-space point (0…1, top-left origin) → a point in the view.
    static func point(_ p: CGPoint, bufferAspect: CGFloat, viewSize: CGSize) -> CGPoint {
        let r = filledRect(bufferAspect: bufferAspect, viewSize: viewSize)
        return CGPoint(x: r.minX + p.x * r.width, y: r.minY + p.y * r.height)
    }

    /// A normalized zone `[x0, y0, x1, y1]` → a rect in the view.
    static func rect(zone z: [Double], bufferAspect: CGFloat, viewSize: CGSize) -> CGRect? {
        guard z.count == 4 else { return nil }
        let a = point(CGPoint(x: z[0], y: z[1]), bufferAspect: bufferAspect, viewSize: viewSize)
        let b = point(CGPoint(x: z[2], y: z[3]), bufferAspect: bufferAspect, viewSize: viewSize)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                      width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}
