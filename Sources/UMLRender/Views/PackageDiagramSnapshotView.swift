import SwiftUI
import UMLDiagram

/// A static rendering of a `PackageDependencyDiagram` from a pre-computed `PackageLayoutModel`:
/// module boxes tinted by their distance from the main sequence, with weighted dependency
/// arrows. Used by the CLI image export (`uml image --package`); the live app draws its own
/// interactive canvas with the richer `ContainerNodeView`.
public struct PackageDiagramSnapshotView: View {
    let layout: PackageLayoutModel
    let padding: CGFloat
    let palette: DiagramPalette
    /// Optional delta tints; `nil` leaves nodes/edges themed as normal.
    let nodeColor: (@Sendable (String) -> Color?)?
    let edgeColor: (@Sendable (String, String) -> Color?)?

    public init(
        layout: PackageLayoutModel, padding: CGFloat = 40, palette: DiagramPalette = .light,
        nodeColor: (@Sendable (String) -> Color?)? = nil,
        edgeColor: (@Sendable (String, String) -> Color?)? = nil
    ) {
        self.layout = layout
        self.padding = padding
        self.palette = palette
        self.nodeColor = nodeColor
        self.edgeColor = edgeColor
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.edges) { edge in
                if let source = layout.frame(for: edge.from), let target = layout.frame(for: edge.to) {
                    RelationshipEdgeView(
                        kind: .dependency,
                        sourceRect: source,
                        targetRect: target,
                        lineWidthScale: min(1 + CGFloat(edge.weight - 1) * 0.35, 3),
                        strokeColor: edgeColor?(edge.from, edge.to)
                    )
                }
            }
            ForEach(layout.nodes) { node in
                moduleBox(node)
            }
        }
        .frame(width: layout.contentSize.width, height: layout.contentSize.height, alignment: .topLeading)
        .padding(padding)
        .background(palette.canvasBackground)
        .environment(\.diagramPalette, palette)
    }

    private func moduleBox(_ node: PackageLayoutModel.NodeFrame) -> some View {
        let module = node.node
        return VStack(spacing: 2) {
            Text(module.name)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(white: 0.1))
            Text("I=\(format(module.instability))  A=\(format(module.abstractness))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(white: 0.3))
        }
        .frame(width: node.rect.width, height: node.rect.height)
        .background(Color(hex: module.zoneColorHex))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(nodeColor?(node.id) ?? Color(white: 0.5), lineWidth: nodeColor?(node.id) == nil ? 1 : 3))
        .position(x: node.rect.midX, y: node.rect.midY)
    }

    private func format(_ value: Double) -> String { String(format: "%.2f", value) }
}
