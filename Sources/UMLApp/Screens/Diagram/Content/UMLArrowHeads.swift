import SwiftUI
import UMLCore

extension Path {
    static func emptyTriangle(at point: CGPoint, angle: CGFloat, size: CGFloat = 12) -> Path {
        Path { path in
            let p1 = point
            let p2 = CGPoint(
                x: point.x - size * cos(angle - .pi / 6),
                y: point.y - size * sin(angle - .pi / 6)
            )
            let p3 = CGPoint(
                x: point.x - size * cos(angle + .pi / 6),
                y: point.y - size * sin(angle + .pi / 6)
            )
            path.move(to: p1)
            path.addLine(to: p2)
            path.addLine(to: p3)
            path.closeSubpath()
        }
    }

    static func openArrow(at point: CGPoint, angle: CGFloat, size: CGFloat = 10) -> Path {
        Path { path in
            let p1 = CGPoint(
                x: point.x - size * cos(angle - .pi / 6),
                y: point.y - size * sin(angle - .pi / 6)
            )
            let p2 = CGPoint(
                x: point.x - size * cos(angle + .pi / 6),
                y: point.y - size * sin(angle + .pi / 6)
            )
            path.move(to: p1)
            path.addLine(to: point)
            path.addLine(to: p2)
        }
    }

    static func filledDiamond(at point: CGPoint, angle: CGFloat, size: CGFloat = 10) -> Path {
        Path { path in
            let tip = point
            let left = CGPoint(
                x: point.x + size * 0.5 * cos(angle - .pi / 2),
                y: point.y + size * 0.5 * sin(angle - .pi / 2)
            )
            let back = CGPoint(
                x: point.x + size * cos(angle),
                y: point.y + size * sin(angle)
            )
            let right = CGPoint(
                x: point.x + size * 0.5 * cos(angle + .pi / 2),
                y: point.y + size * 0.5 * sin(angle + .pi / 2)
            )
            path.move(to: tip)
            path.addLine(to: left)
            path.addLine(to: back)
            path.addLine(to: right)
            path.closeSubpath()

        }
    }
}

extension Relationship.Kind {
    var strokeStyle: StrokeStyle {
        switch self {
        case .conformance, .dependency:
            return StrokeStyle(lineWidth: 1.5, dash: [8, 4])
        case .extension:
            return StrokeStyle(lineWidth: 1.5, dash: [4, 4])
        default:
            return StrokeStyle(lineWidth: 1.5)
        }
    }

    var hasSourceDecoration: Bool {
        self == .composition || self == .aggregation
    }

    var isSourceDecorationFilled: Bool {
        self == .composition
    }
}
