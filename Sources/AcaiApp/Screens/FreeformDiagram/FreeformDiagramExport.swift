import SwiftUI
import AcaiRender

extension FreeformDiagramViewModel {
    /// Renders the whole diagram — not just whatever's currently scrolled into view — the same
    /// way `ClassDiagramViewModel`/`CallGraphViewModel`/etc. do: compute the content's own bounds,
    /// normalize every position to them, then hand a non-interactive snapshot view to
    /// `DiagramImageRenderer`.
    func exportPNGData(scale: CGFloat = 2) throws -> Data {
        let sizes = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, nodeSize($0.id)) })
        let originalContext = FreeformDiagramExportContext(nodes: nodes, edges: edges)
        let originalSequence = SequenceEditor(context: originalContext)
        let bounds = FreeformDiagramContentBounds(
            nodes: nodes, sizes: sizes,
            sequenceLayout: originalSequence.sequenceLayout, sequenceAnchorY: originalSequence.sequenceAnchorY
        ).rect

        let dx = -bounds.minX
        let dy = -bounds.minY
        let translatedNodes = nodes.map { node -> FreeformDiagram.Node in
            var copy = node
            copy.positionX += Double(dx)
            copy.positionY += Double(dy)
            return copy
        }

        let exportContext = FreeformDiagramExportContext(nodes: translatedNodes, edges: edges)
        let sequenceEditor = SequenceEditor(context: exportContext)
        let messageEdgeIDs = Set(sequenceEditor.messageEdges.map(\.id))
        let ordinaryEdges = edges.filter { !messageEdgeIDs.contains($0.id) }
        let positions = Dictionary(
            uniqueKeysWithValues: translatedNodes.map { ($0.id, CGPoint(x: $0.positionX, y: $0.positionY)) })

        let view = FreeformDiagramSnapshotView(
            containerNodes: translatedNodes.filter(\.isResizable).sorted { $0.drawOrder < $1.drawOrder },
            regularNodes: translatedNodes
                .filter { !$0.isResizable && $0.content.canvasBehavior.rendersAsFreeNode }
                .sorted { $0.drawOrder < $1.drawOrder },
            lifelineNodes: sequenceEditor.lifelineNodes,
            edges: ordinaryEdges,
            sizes: sizes,
            positions: positions,
            sequenceLayout: sequenceEditor.sequenceLayout,
            sequenceAnchorY: sequenceEditor.sequenceAnchorY,
            contentSize: bounds.size
        )

        return try DiagramImageRenderer().render(view, contentSize: bounds.size, scale: scale)
    }
}
