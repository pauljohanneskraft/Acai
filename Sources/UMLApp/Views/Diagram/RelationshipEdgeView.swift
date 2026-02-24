import SwiftUI
import UMLCore

/// Draws a relationship line between two node rectangles with appropriate
/// UML arrow heads and line styles.
struct RelationshipEdgeView: View {
    let edge: DiagramEdge
    let sourceRect: CGRect
    let targetRect: CGRect

    private let edgeColor = Color(white: 0.4)

    var body: some View {
        let (startPoint, endPoint) = connectionPoints(from: sourceRect, to: targetRect)
        let lineAngle = UMLArrowHeads.angle(from: startPoint, to: endPoint)

        // Main line path.
        let linePath = Path { path in
            path.move(to: startPoint)
            path.addLine(to: endPoint)
        }

        // Arrow head path at target.
        let arrowPath = Path { path in
            switch edge.kind {
            case .inheritance, .conformance:
                UMLArrowHeads.emptyTriangle(in: &path, at: endPoint, angle: lineAngle)
            case .association, .dependency:
                UMLArrowHeads.openArrow(in: &path, at: endPoint, angle: lineAngle)
            case .extension:
                UMLArrowHeads.emptyTriangle(in: &path, at: endPoint, angle: lineAngle)
            case .nesting:
                UMLArrowHeads.openArrow(in: &path, at: endPoint, angle: lineAngle)
            default:
                break
            }
        }

        // Source decoration path (diamond for composition/aggregation).
        let sourceAngle = UMLArrowHeads.angle(from: endPoint, to: startPoint)
        let sourcePath = Path { path in
            if UMLArrowHeads.hasSourceDecoration(for: edge.kind) {
                UMLArrowHeads.filledDiamond(in: &path, at: startPoint, angle: sourceAngle)
            }
        }

        let style = UMLArrowHeads.strokeStyle(for: edge.kind)

        ZStack {
            // Line
            linePath.stroke(edgeColor, style: style)

            // Arrow head at target
            switch edge.kind {
            case .inheritance, .conformance, .extension:
                // Empty triangle: stroke only (unfilled)
                arrowPath.stroke(edgeColor, lineWidth: 1.5)
                arrowPath.fill(Color(white: 0.96))
            case .association, .dependency, .nesting:
                // Open arrow: stroke only
                arrowPath.stroke(edgeColor, lineWidth: 1.5)
            default:
                EmptyView()
            }

            // Diamond at source
            if UMLArrowHeads.hasSourceDecoration(for: edge.kind) {
                if UMLArrowHeads.isSourceDecorationFilled(for: edge.kind) {
                    sourcePath.fill(edgeColor)
                } else {
                    sourcePath.stroke(edgeColor, lineWidth: 1.5)
                    sourcePath.fill(Color(white: 0.96))
                }
            }
        }
    }

    // MARK: - Connection Points

    /// Computes the points where the edge line intersects the source and target node rectangles.
    private func connectionPoints(from source: CGRect, to target: CGRect) -> (CGPoint, CGPoint) {
        let sourceCenter = CGPoint(x: source.midX, y: source.midY)
        let targetCenter = CGPoint(x: target.midX, y: target.midY)

        let start = intersectionPoint(from: sourceCenter, to: targetCenter, rect: source)
        let end = intersectionPoint(from: targetCenter, to: sourceCenter, rect: target)

        return (start, end)
    }

    /// Finds the intersection of a line from `from` toward `to` with the boundary of `rect`.
    private func intersectionPoint(from: CGPoint, to: CGPoint, rect: CGRect) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y

        guard abs(dx) > 0.001 || abs(dy) > 0.001 else { return from }

        var tMin: CGFloat = .greatestFiniteMagnitude

        // Check intersection with each edge of the rectangle.
        // Right edge
        if dx != 0 {
            let t = (rect.maxX - from.x) / dx
            if t > 0 {
                let y = from.y + t * dy
                if y >= rect.minY && y <= rect.maxY {
                    tMin = min(tMin, t)
                }
            }
        }
        // Left edge
        if dx != 0 {
            let t = (rect.minX - from.x) / dx
            if t > 0 {
                let y = from.y + t * dy
                if y >= rect.minY && y <= rect.maxY {
                    tMin = min(tMin, t)
                }
            }
        }
        // Bottom edge
        if dy != 0 {
            let t = (rect.maxY - from.y) / dy
            if t > 0 {
                let x = from.x + t * dx
                if x >= rect.minX && x <= rect.maxX {
                    tMin = min(tMin, t)
                }
            }
        }
        // Top edge
        if dy != 0 {
            let t = (rect.minY - from.y) / dy
            if t > 0 {
                let x = from.x + t * dx
                if x >= rect.minX && x <= rect.maxX {
                    tMin = min(tMin, t)
                }
            }
        }

        if tMin < .greatestFiniteMagnitude {
            return CGPoint(x: from.x + tMin * dx, y: from.y + tMin * dy)
        }
        return from
    }
}
