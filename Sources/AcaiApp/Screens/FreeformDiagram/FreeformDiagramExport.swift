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

/// A minimal, otherwise-unused `FreeformEditingContext` so export can reuse `SequenceEditor`'s
/// lifeline/message/fragment layout logic instead of duplicating it — the mutating requirements
/// are never called on this path.
private final class FreeformDiagramExportContext: FreeformEditingContext {
    var nodes: [FreeformDiagram.Node]
    var edges: [FreeformDiagram.Edge]
    var selectedNodeIDs: Set<String> = []
    var selectedEdgeID: String?
    var selectionOrder: [String] { [] }

    init(nodes: [FreeformDiagram.Node], edges: [FreeformDiagram.Edge]) {
        self.nodes = nodes
        self.edges = edges
    }

    func recordUndo(coalescingKey: AnyHashable?) {}
    func save() {}
    func removeNodes(_ ids: Set<String>) {}
}

/// The union of everything an export needs to fit: every container/regular node's rect, plus
/// (when the diagram has sequence content) every lifeline header, combined-fragment frame, and a
/// margin for a self-loop message hanging off the right-most lifeline.
private struct FreeformDiagramContentBounds {
    let nodes: [FreeformDiagram.Node]
    let sizes: [String: CGSize]
    let sequenceLayout: SequenceLayoutModel?
    let sequenceAnchorY: CGFloat

    var rect: CGRect {
        var rects: [CGRect] = nodes.compactMap { node in
            guard node.content.canvasBehavior.rendersAsFreeNode || node.isResizable else {
                // Lifelines/fragments render through the sequence layer, accounted for below.
                return nil
            }
            let size = sizes[node.id] ?? CGSize(width: 120, height: 60)
            return CGRect(
                x: node.positionX - size.width / 2, y: node.positionY - size.height / 2,
                width: size.width, height: size.height)
        }

        if let sequenceLayout {
            let headerRects = sequenceLayout.participants.map { $0.headerRect.offsetBy(dx: 0, dy: sequenceAnchorY) }
            let fragmentRects = sequenceLayout.fragments.map { $0.rect.offsetBy(dx: 0, dy: sequenceAnchorY) }
            rects.append(contentsOf: headerRects)
            rects.append(contentsOf: fragmentRects)
            let maxHeaderX = sequenceLayout.participants.map(\.headerRect.maxX).max() ?? 0
            rects.append(CGRect(
                x: maxHeaderX, y: sequenceAnchorY,
                width: SequenceLayoutModel.selfLoopWidth, height: sequenceLayout.contentSize.height))
        }

        guard let first = rects.first else {
            return CGRect(x: 0, y: 0, width: 200, height: 120)
        }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }
}
