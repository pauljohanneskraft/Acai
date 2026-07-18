import SwiftUI
import AcaiDiagram

/// A static rendering of a `CallGraph` from a pre-computed `CallGraphLayoutModel`: method boxes
/// (in-scope solid, out-of-scope callee leaves dashed and lighter) joined by call arrows whose
/// thickness encodes multiplicity. Used by the CLI image export (`acai image --call-graph`).
public struct CallGraphSnapshotView: View {
    let layout: CallGraphLayoutModel
    let padding: CGFloat
    let palette: DiagramPalette
    /// Optional delta tints; `nil` leaves nodes/edges themed as normal.
    let nodeColor: (@Sendable (String) -> Color?)?
    let edgeColor: (@Sendable (String, String) -> Color?)?

    public init(
        layout: CallGraphLayoutModel, padding: CGFloat = 40, palette: DiagramPalette = .light,
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
                methodBox(node)
            }
        }
        .frame(width: layout.contentSize.width, height: layout.contentSize.height, alignment: .topLeading)
        .padding(padding)
        .background(palette.canvasBackground)
        .environment(\.diagramPalette, palette)
    }

    private func methodBox(_ node: CallGraphLayoutModel.NodeFrame) -> some View {
        let method = node.node
        return Text(method.label)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(palette.primaryInk)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .frame(width: node.rect.width, height: node.rect.height)
            .background(method.inScope ? palette.callGraphInScopeFill : palette.callGraphOutOfScopeFill)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        nodeColor?(node.id) ?? palette.neutralBorder,
                        style: StrokeStyle(
                            lineWidth: nodeColor?(node.id) == nil ? 1 : 3, dash: method.inScope ? [] : [4, 3])
                    )
            )
            .position(x: node.rect.midX, y: node.rect.midY)
    }
}
