import Foundation
import AcaiCore
import AcaiDiagram

/// Converts a static call graph into an editable freeform diagram: each method becomes a
/// `.method` node (the same monospaced box the generated view shows) and every call a dependency
/// edge. The scope's coverage/leaf distinction isn't carried over by default — a hand-edited call
/// graph has no analysis behind it — but when `includeMetricsNote` is set (B22), one read-only
/// `.note` node reporting the resolved/total call-site coverage is appended instead of silently
/// dropping the figure.
struct CallGraphFreeformConversion: FreeformConversion {
    let context: FreeformConversionContext
    let includeMetricsNote: Bool
    private let graph: CallGraph

    init(context: FreeformConversionContext, scope: CallGraphScope, includeMetricsNote: Bool) {
        self.context = context
        self.includeMetricsNote = includeMetricsNote
        self.graph = CallGraphBuilder(scope: scope).build(from: context.artifact)
    }

    func items() -> [CallGraph.Node] {
        graph.nodes
    }

    func sourceID(for item: CallGraph.Node) -> String {
        item.id
    }

    func defaultPosition(index: Int) -> CGPoint {
        CGPoint(x: CGFloat(index) * 200 + 120, y: 120)
    }

    func makeNode(for item: CallGraph.Node, id: String, position: CGPoint) -> FreeformDiagram.Node {
        FreeformDiagram.Node(
            id: id,
            name: item.label,
            content: .method,
            positionX: Double(position.x),
            positionY: Double(position.y)
        )
    }

    func makeEdges(idsBySourceID: [String: String]) -> [FreeformDiagram.Edge] {
        graph.edges.compactMap { edge in
            guard let source = idsBySourceID[edge.from],
                  let target = idsBySourceID[edge.to] else { return nil }
            return FreeformDiagram.Edge(sourceNodeID: source, targetNodeID: target, kind: .dependency)
        }
    }

    func metricsFooterNodes(existingNodes: [FreeformDiagram.Node]) -> [FreeformDiagram.Node] {
        guard includeMetricsNote, !graph.nodes.isEmpty else { return [] }
        let maxY = existingNodes.map(\.positionY).max() ?? 120
        return [FreeformDiagram.Node(
            name: "Call Graph Coverage (read-only)",
            content: .note(text: graph.coverage.metricsNoteText),
            positionX: 120,
            positionY: maxY + 220
        )]
    }
}
