import SwiftUI

/// The head zone and the hand skeleton, drawn over the camera preview.
///
/// This is what makes the detection visible: point the phone at yourself and you can see exactly
/// what the detector sees — the zone tracking your head, the joints it found, and the moment a
/// fingertip crosses into the zone (the box turns red).
struct DetectionOverlay: View {
    let zone: [Double]?
    let hands: [[CGPoint]]
    let touching: Bool
    let bufferAspect: CGFloat

    var body: some View {
        Canvas { ctx, size in
            if let zone, let rect = PreviewGeometry.rect(zone: zone, bufferAspect: bufferAspect,
                                                         viewSize: size) {
                let path = Path(roundedRect: rect, cornerRadius: 12)
                ctx.stroke(path, with: .color(touching ? .red : .green), lineWidth: 3)
                ctx.fill(path, with: .color((touching ? Color.red : Color.green).opacity(0.10)))
            }
            for hand in hands {
                draw(hand: hand, in: &ctx, size: size)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(hand: [CGPoint], in ctx: inout GraphicsContext, size: CGSize) {
        guard hand.count >= 21 else { return }
        func viewPoint(_ i: Int) -> CGPoint? {
            let p = hand[i]
            guard p.x >= 0, p.y >= 0 else { return nil }   // (-1, -1) = joint not found
            return PreviewGeometry.point(p, bufferAspect: bufferAspect, viewSize: size)
        }

        var bones = Path()
        for chain in handConnections {
            for (a, b) in zip(chain, chain.dropFirst()) {
                guard let pa = viewPoint(a), let pb = viewPoint(b) else { continue }
                bones.move(to: pa)
                bones.addLine(to: pb)
            }
        }
        ctx.stroke(bones, with: .color(.white.opacity(0.85)), lineWidth: 2)

        for i in 0..<21 {
            guard let p = viewPoint(i) else { continue }
            let isTip = fingertipIndices.contains(i)
            let r: CGFloat = isTip ? 5 : 3
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            ctx.fill(dot, with: .color(isTip ? .yellow : .white))
        }
    }
}

/// MediaPipe's 21-landmark skeleton: the palm ridge plus one chain per finger.
private let handConnections: [[Int]] = [
    [0, 1, 2, 3, 4],           // thumb
    [0, 5, 6, 7, 8],           // index
    [0, 9, 10, 11, 12],        // middle
    [0, 13, 14, 15, 16],       // ring
    [0, 17, 18, 19, 20],       // little
    [5, 9, 13, 17],            // knuckles
]
