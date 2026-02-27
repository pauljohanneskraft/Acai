import SwiftUI
import UMLCore

/// Utilities for drawing UML relationship arrow heads and decorations.
enum UMLArrowHeads {

    private static let arrowSize: CGFloat = 12
    private static let diamondSize: CGFloat = 10

    // MARK: - Target (arrow head) decorations

    /// Draws an empty (unfilled) triangle arrowhead for inheritance/conformance.
    static func emptyTriangle(in path: inout Path, at point: CGPoint, angle: CGFloat) {
        let size = arrowSize
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

    /// Draws an open V-shaped arrowhead for association/dependency.
    static func openArrow(in path: inout Path, at point: CGPoint, angle: CGFloat) {
        let size = arrowSize * 0.8
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

    // MARK: - Source decorations

    /// Draws a filled diamond for composition.
    static func filledDiamond(in path: inout Path, at point: CGPoint, angle: CGFloat) {
        let size = diamondSize
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

    /// Draws an empty (unfilled) diamond for aggregation.
    static func emptyDiamond(in path: inout Path, at point: CGPoint, angle: CGFloat) {
        // Same shape as filledDiamond — filled vs unfilled is controlled by stroke/fill at draw time.
        filledDiamond(in: &path, at: point, angle: angle)
    }

    // MARK: - Helpers

    /// Computes the angle in radians from one point to another.
    static func angle(from start: CGPoint, to end: CGPoint) -> CGFloat {
        atan2(end.y - start.y, end.x - start.x)
    }

    /// Returns the stroke style for a given relationship kind.
    static func strokeStyle(for kind: Relationship.Kind) -> StrokeStyle {
        switch kind {
        case .conformance, .dependency:
            return StrokeStyle(lineWidth: 1.5, dash: [8, 4])
        case .extension:
            return StrokeStyle(lineWidth: 1.5, dash: [4, 4])
        default:
            return StrokeStyle(lineWidth: 1.5)
        }
    }

    /// Whether the relationship has a source-side decoration (diamond).
    static func hasSourceDecoration(for kind: Relationship.Kind) -> Bool {
        kind == .composition || kind == .aggregation
    }

    /// Whether the source decoration should be filled.
    static func isSourceDecorationFilled(for kind: Relationship.Kind) -> Bool {
        kind == .composition
    }
}
