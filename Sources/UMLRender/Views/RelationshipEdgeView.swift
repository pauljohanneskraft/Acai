import SwiftUI
import UMLCore

/// Draws a relationship line between two node rectangles with appropriate
/// UML arrow heads and line styles.
public struct RelationshipEdgeView: View, Equatable {
    let kind: Relationship.Kind
    let sourceRect: CGRect
    let targetRect: CGRect
    /// Optional text drawn beside the line's midpoint (e.g. a state-transition's
    /// `event [guard] / action` label).
    let label: String?
    /// Multiplicity drawn near the source (tail) endpoint, e.g. `1` / `*` / `0..1`.
    let sourceLabel: String?
    /// Multiplicity drawn near the target (head) endpoint.
    let targetLabel: String?
    /// Multiplies the kind's default line width — used by the package diagram to encode a
    /// dependency's weight as thickness. Defaults to `1` (unchanged for class/state edges).
    let lineWidthScale: CGFloat

    public init(
        kind: Relationship.Kind,
        sourceRect: CGRect,
        targetRect: CGRect,
        label: String? = nil,
        sourceLabel: String? = nil,
        targetLabel: String? = nil,
        lineWidthScale: CGFloat = 1
    ) {
        self.kind = kind
        self.sourceRect = sourceRect
        self.targetRect = targetRect
        self.label = label
        self.sourceLabel = sourceLabel
        self.targetLabel = targetLabel
        self.lineWidthScale = lineWidthScale
    }

    nonisolated public static func == (lhs: RelationshipEdgeView, rhs: RelationshipEdgeView) -> Bool {
        lhs.sourceRect == rhs.sourceRect && lhs.targetRect == rhs.targetRect
            && lhs.kind == rhs.kind && lhs.label == rhs.label && lhs.lineWidthScale == rhs.lineWidthScale
            && lhs.sourceLabel == rhs.sourceLabel && lhs.targetLabel == rhs.targetLabel
    }

    @Environment(\.diagramPalette) private var palette

    public var body: some View {
        // Connection points are derived synchronously from the rects (rather than via
        // `@State`/`onChange`) so the view renders correctly in a one-shot `ImageRenderer`
        // snapshot, where change callbacks never fire.
        let (startPoint, endPoint) = connectionPoints(from: sourceRect, to: targetRect)
        ZStack {
            Group {
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

                let baseStyle = kind.strokeStyle
                let style = StrokeStyle(
                    lineWidth: baseStyle.lineWidth * lineWidthScale,
                    lineCap: baseStyle.lineCap,
                    lineJoin: baseStyle.lineJoin,
                    dash: baseStyle.dash,
                    dashPhase: baseStyle.dashPhase
                )

                linePath.stroke(palette.edgeLine, style: style)

                // Arrow head at target
                switch kind {
                case .inheritance, .conformance, .extension:
                    // Empty triangle: stroke only (unfilled)
                    arrowPath.fill(palette.edgeDecorationFill)
                    arrowPath.stroke(palette.edgeLine, lineWidth: style.lineWidth)
                case .association, .dependency, .nesting:
                    // Open arrow: stroke only
                    arrowPath.stroke(palette.edgeLine, lineWidth: style.lineWidth)
                default:
                    EmptyView()
                }

                // Diamond at source
                if kind.hasSourceDecoration {
                    sourcePath.fill(
                        kind.isSourceDecorationFilled
                            ? palette.edgeLine
                            : palette.edgeDecorationFill
                    )
                    sourcePath.stroke(palette.edgeLine, lineWidth: style.lineWidth)
                }
            }

            if let label {
                // Explicit ink so the label stays readable in dark mode against
                // the light canvas (matching SequenceMessageView's labels).
                Text(label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(palette.edgeLabelInk)
                    .position(
                        x: (startPoint.x + endPoint.x) / 2,
                        y: (startPoint.y + endPoint.y) / 2 - 8
                    )
            }

            if let sourceLabel {
                multiplicityLabel(sourceLabel, near: startPoint, toward: endPoint)
            }
            if let targetLabel {
                multiplicityLabel(targetLabel, near: endPoint, toward: startPoint)
            }
        }
    }

    /// A small cardinality label nudged in from `anchor` along the edge (and to one side)
    /// so it sits beside the endpoint rather than under the node or the arrow head.
    private func multiplicityLabel(_ text: String, near anchor: CGPoint, toward other: CGPoint) -> some View {
        let dx = other.x - anchor.x
        let dy = other.y - anchor.y
        let length = max(0.001, (dx * dx + dy * dy).squareRoot())
        let (ux, uy) = (dx / length, dy / length)
        return Text(text)
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(palette.edgeLabelInk)
            .position(x: anchor.x + ux * 16 - uy * 9, y: anchor.y + uy * 16 + ux * 9)
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
