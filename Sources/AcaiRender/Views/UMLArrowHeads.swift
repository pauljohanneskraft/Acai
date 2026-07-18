import SwiftUI
import AcaiCore

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
            let back = CGPoint(
                x: point.x - size * cos(angle),
                y: point.y - size * sin(angle)
            )
            let width = size / 2
            let midX = point.x - width * cos(angle)
            let midY = point.y - width * sin(angle)
            let left = CGPoint(
                x: midX + width * cos(angle - .pi / 2),
                y: midY + width * sin(angle - .pi / 2)
            )
            let right = CGPoint(
                x: midX + width * cos(angle + .pi / 2),
                y: midY + width * sin(angle + .pi / 2)
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
