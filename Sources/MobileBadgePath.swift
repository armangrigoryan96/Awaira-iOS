import SwiftUI

/// iOS counterpart to the desktop SVG-path renderer. Badge glyphs are authored in a 20×20 box.
struct MobileBadgePath: Shape {
    let commands: String

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 20
        let offset = CGPoint(x: rect.minX + (rect.width - 20 * scale) / 2,
                             y: rect.minY + (rect.height - 20 * scale) / 2)
        func map(_ point: CGPoint) -> CGPoint { CGPoint(x: offset.x + point.x * scale, y: offset.y + point.y * scale) }

        var path = Path(), current = CGPoint.zero, subpathStart = CGPoint.zero
        var tokens = Tokenizer(commands)
        while let op = tokens.nextOperator() {
            switch op {
            case "M":
                current = CGPoint(x: tokens.number(), y: tokens.number())
                subpathStart = current
                path.move(to: map(current))
                while tokens.peekIsNumber { current = CGPoint(x: tokens.number(), y: tokens.number()); path.addLine(to: map(current)) }
            case "L":
                repeat { current = CGPoint(x: tokens.number(), y: tokens.number()); path.addLine(to: map(current)) } while tokens.peekIsNumber
            case "H":
                repeat { current.x = tokens.number(); path.addLine(to: map(current)) } while tokens.peekIsNumber
            case "V":
                repeat { current.y = tokens.number(); path.addLine(to: map(current)) } while tokens.peekIsNumber
            case "C":
                repeat {
                    let c1 = CGPoint(x: tokens.number(), y: tokens.number())
                    let c2 = CGPoint(x: tokens.number(), y: tokens.number())
                    current = CGPoint(x: tokens.number(), y: tokens.number())
                    path.addCurve(to: map(current), control1: map(c1), control2: map(c2))
                } while tokens.peekIsNumber
            case "A":
                repeat {
                    let rx = tokens.number(), ry = tokens.number(), rotation = tokens.number()
                    let largeArc = tokens.number() != 0, sweep = tokens.number() != 0
                    let end = CGPoint(x: tokens.number(), y: tokens.number())
                    for point in Self.flattenArc(from: current, to: end, rx: rx, ry: ry, rotation: rotation, largeArc: largeArc, sweep: sweep) { path.addLine(to: map(point)) }
                    current = end
                } while tokens.peekIsNumber
            case "Z": path.closeSubpath(); current = subpathStart
            default: break
            }
        }
        return path
    }

    private static func flattenArc(from start: CGPoint, to end: CGPoint, rx: CGFloat, ry: CGFloat,
                                   rotation: CGFloat, largeArc: Bool, sweep: Bool) -> [CGPoint] {
        guard rx != 0, ry != 0, start != end else { return [end] }
        var rx = abs(rx), ry = abs(ry)
        let phi = rotation * .pi / 180, cosPhi = cos(phi), sinPhi = sin(phi)
        let dx2 = (start.x - end.x) / 2, dy2 = (start.y - end.y) / 2
        let x1 = cosPhi * dx2 + sinPhi * dy2, y1 = -sinPhi * dx2 + cosPhi * dy2
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { let factor = lambda.squareRoot(); rx *= factor; ry *= factor }
        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coefficient = denominator == 0 ? 0 : (numerator / denominator).squareRoot()
        if largeArc == sweep { coefficient = -coefficient }
        let cx1 = coefficient * rx * y1 / ry, cy1 = -coefficient * ry * x1 / rx
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let length = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            guard length > 0 else { return 0 }
            let value = acos(min(1, max(-1, (ux * vx + uy * vy) / length)))
            return (ux * vy - uy * vx) < 0 ? -value : value
        }
        let ux = (x1 - cx1) / rx, uy = (y1 - cy1) / ry, vx = (-x1 - cx1) / rx, vy = (-y1 - cy1) / ry
        let theta = angle(1, 0, ux, uy)
        var delta = angle(ux, uy, vx, vy)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }
        let centerX = cosPhi * cx1 - sinPhi * cy1 + (start.x + end.x) / 2
        let centerY = sinPhi * cx1 + cosPhi * cy1 + (start.y + end.y) / 2
        let steps = max(2, Int((abs(delta) / (.pi / 90)).rounded(.up)))
        return (1...steps).map { step in
            let t = theta + delta * CGFloat(step) / CGFloat(steps)
            return CGPoint(x: cosPhi * rx * cos(t) - sinPhi * ry * sin(t) + centerX,
                           y: sinPhi * rx * cos(t) + cosPhi * ry * sin(t) + centerY)
        }
    }

    private struct Tokenizer {
        private let characters: [Character]
        private var index = 0
        init(_ source: String) { characters = Array(source) }
        private mutating func skipSeparators() { while index < characters.count, characters[index] == "," || characters[index].isWhitespace { index += 1 } }
        var peekIsNumber: Bool {
            var next = index
            while next < characters.count, characters[next] == "," || characters[next].isWhitespace { next += 1 }
            guard next < characters.count else { return false }
            return characters[next].isNumber || characters[next] == "-" || characters[next] == "+" || characters[next] == "."
        }
        mutating func nextOperator() -> Character? { skipSeparators(); guard index < characters.count else { return nil }; defer { index += 1 }; return characters[index] }
        mutating func number() -> CGFloat {
            skipSeparators(); var value = ""
            if index < characters.count, characters[index] == "-" || characters[index] == "+" { value.append(characters[index]); index += 1 }
            while index < characters.count, characters[index].isNumber || characters[index] == "." { value.append(characters[index]); index += 1 }
            return CGFloat(Double(value) ?? 0)
        }
    }
}

struct MobileBadgeIconView: View {
    let path: String
    let size: CGFloat
    let lineWidth: CGFloat
    let color: Color

    var body: some View {
        MobileBadgePath(commands: path)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth * size / 20, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}
