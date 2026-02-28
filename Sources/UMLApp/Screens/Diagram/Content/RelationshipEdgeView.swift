import SwiftUI
import UMLCore

/// Draws a relationship line between two node rectangles with appropriate
/// UML arrow heads and line styles.
struct RelationshipEdgeView: View, Equatable {
    let kind: Relationship.Kind
    let sourceRect: CGRect
    let targetRect: CGRect
    
    nonisolated static func == (lhs: RelationshipEdgeView, rhs: RelationshipEdgeView) -> Bool {
        lhs.sourceRect == rhs.sourceRect && lhs.targetRect == rhs.targetRect && lhs.kind == rhs.kind
    }
    
    @State private var startPoint: CGPoint?
    @State private var endPoint: CGPoint?

    private let edgeColor = Color(white: 0.4)

    var body: some View {
        ZStack {
            if let startPoint, let endPoint {
                let lineAngle = Self.angle(from: startPoint, to: endPoint)

                let linePath = Path { path in
                    path.move(to: startPoint)
                    path.addLine(to: endPoint)
                }

                let arrowPath: Path = switch kind {
                case .inheritance, .conformance:
                    .emptyTriangle(at: endPoint, angle: lineAngle)
                case .association, .dependency:
                    .openArrow(at: endPoint, angle: lineAngle)
                case .extension:
                    .emptyTriangle(at: endPoint, angle: lineAngle)
                case .nesting:
                    .openArrow(at: endPoint, angle: lineAngle)
                default:
                    .init()
                }

                let sourcePath: Path = if kind.hasSourceDecoration {
                    .filledDiamond(at: startPoint, angle: lineAngle - .pi)
                } else { .init() }

                let style = kind.strokeStyle

                
                linePath.stroke(edgeColor, style: style)

                // Arrow head at target
                switch kind {
                case .inheritance, .conformance, .extension:
                    // Empty triangle: stroke only (unfilled)
                    arrowPath.fill(Color(white: 0.96))
                    arrowPath.stroke(edgeColor, lineWidth: style.lineWidth)
                case .association, .dependency, .nesting:
                    // Open arrow: stroke only
                    arrowPath.stroke(edgeColor, lineWidth: style.lineWidth)
                default:
                    EmptyView()
                }

                // Diamond at source
                if kind.hasSourceDecoration {
                    sourcePath.fill(
                        kind.isSourceDecorationFilled
                            ? edgeColor
                            : Color(white: 0.96)
                    )
                    sourcePath.stroke(edgeColor, lineWidth: style.lineWidth)
                }
            }
        }
        .onChange(of: self) {
            let (startPoint, endPoint) = connectionPoints(from: sourceRect, to: targetRect)
            self.startPoint = startPoint
            self.endPoint = endPoint
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

        let noHit: CGFloat = .greatestFiniteMagnitude
        let yRange = rect.minY...rect.maxY
        let xRange = rect.minX...rect.maxX

        let yCross = (delta: dy, origin: from.y, range: yRange)
        let xCross = (delta: dx, origin: from.x, range: xRange)

        let candidatesT: [CGFloat] = [
            Self.edgeT(delta: dx, from: from.x, edge: rect.maxX, cross: yCross),
            Self.edgeT(delta: dx, from: from.x, edge: rect.minX, cross: yCross),
            Self.edgeT(delta: dy, from: from.y, edge: rect.maxY, cross: xCross),
            Self.edgeT(delta: dy, from: from.y, edge: rect.minY, cross: xCross)
        ]

        let tMin = candidatesT.filter { $0 > 0 }.min() ?? noHit
        if tMin < noHit {
            return CGPoint(x: from.x + tMin * dx, y: from.y + tMin * dy)
        }
        return from
    }

    private static func angle(from start: CGPoint, to end: CGPoint) -> CGFloat {
        atan2(end.y - start.y, end.x - start.x)
    }

    /// Parametric t for ray intersection with one rectangle edge; returns `.greatestFiniteMagnitude` on miss.
    private static func edgeT(
        delta: CGFloat, from: CGFloat, edge: CGFloat,
        cross: (delta: CGFloat, origin: CGFloat, range: ClosedRange<CGFloat>)
    ) -> CGFloat {
        guard delta != 0 else { return .greatestFiniteMagnitude }
        let t = (edge - from) / delta
        guard t > 0 else { return .greatestFiniteMagnitude }
        let crossValue = cross.origin + t * cross.delta
        return cross.range.contains(crossValue) ? t : .greatestFiniteMagnitude
    }
}
