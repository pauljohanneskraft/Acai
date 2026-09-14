import SwiftUI
import AcaiDiagram
import AcaiRender

/// A static, non-interactive rendering of a freeform diagram, used to produce image exports.
/// Composes the same `FreeformNodeView` / `RelationshipEdgeView` / `SequenceEnsembleView` the live
/// canvas uses, but without gestures, selection or the infinite pannable canvas — mirroring
/// `DiagramSnapshotView`'s role for generated diagrams.
///
/// All node positions are expected pre-normalized to the content's own space (top-left at the
/// origin); the view sizes itself to `contentSize` plus a uniform `padding`.
struct FreeformDiagramSnapshotView: View {
    let containerNodes: [FreeformDiagram.Node]
    let regularNodes: [FreeformDiagram.Node]
    let lifelineNodes: [FreeformDiagram.Node]
    let edges: [FreeformDiagram.Edge]
    let sizes: [String: CGSize]
    let positions: [String: CGPoint]
    let sequenceLayout: SequenceLayoutModel?
    let sequenceAnchorY: CGFloat
    let contentSize: CGSize
    let padding: CGFloat
    let palette: DiagramPalette

    init(
        containerNodes: [FreeformDiagram.Node],
        regularNodes: [FreeformDiagram.Node],
        lifelineNodes: [FreeformDiagram.Node],
        edges: [FreeformDiagram.Edge],
        sizes: [String: CGSize],
        positions: [String: CGPoint],
        sequenceLayout: SequenceLayoutModel?,
        sequenceAnchorY: CGFloat,
        contentSize: CGSize,
        padding: CGFloat = DiagramImageRenderer.defaultPadding,
        palette: DiagramPalette = .light
    ) {
        self.containerNodes = containerNodes
        self.regularNodes = regularNodes
        self.lifelineNodes = lifelineNodes
        self.edges = edges
        self.sizes = sizes
        self.positions = positions
        self.sequenceLayout = sequenceLayout
        self.sequenceAnchorY = sequenceAnchorY
        self.contentSize = contentSize
        self.padding = padding
        self.palette = palette
    }

    private func size(for id: String) -> CGSize {
        sizes[id] ?? CGSize(width: 120, height: 60)
    }

    private func rect(for id: String) -> CGRect? {
        guard let pos = positions[id] else { return nil }
        let size = size(for: id)
        return CGRect(x: pos.x - size.width / 2, y: pos.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    var body: some View {
        ZStack {
            ForEach(containerNodes) { node in
                nodeView(node)
            }

            if let sequenceLayout {
                SequenceEnsembleView(layout: sequenceLayout)
                    .offset(y: sequenceAnchorY)
                ForEach(lifelineNodes) { node in
                    lifelineHeader(node)
                }
            }

            ForEach(regularNodes) { node in
                nodeView(node)
            }

            ForEach(edges) { edge in
                if let sourceRect = rect(for: edge.sourceNodeID), let targetRect = rect(for: edge.targetNodeID) {
                    RelationshipEdgeView(
                        kind: edge.kind, sourceRect: sourceRect, targetRect: targetRect,
                        label: edge.transition?.label ?? edge.label
                    )
                }
            }
        }
        .frame(width: contentSize.width, height: contentSize.height)
        .padding(padding)
        .background(palette.canvasBackground)
        .environment(\.diagramPalette, palette)
    }

    private func nodeView(_ node: FreeformDiagram.Node) -> some View {
        let size = size(for: node.id)
        return FreeformNodeView(node: node, isSelected: false, size: size)
            .frame(width: size.width, height: size.height)
            .position(x: node.positionX, y: node.positionY)
    }

    private func lifelineHeader(_ node: FreeformDiagram.Node) -> some View {
        let kind: SequenceDiagram.Participant.Kind =
            if case .lifeline(let k) = node.content { k } else { .object }
        let size = size(for: node.id)
        return ParticipantHeaderView(name: node.name, kind: kind, isSelected: false)
            .frame(width: size.width, height: size.height)
            .position(x: node.positionX, y: sequenceAnchorY + SequenceLayoutModel.headerHeight / 2)
    }
}
