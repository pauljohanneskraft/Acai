import Foundation
import AcaiCore
import AcaiDiagram

/// Converts a static call graph into an editable freeform diagram: each method becomes a
/// `.method` node (the same monospaced box the generated view shows) and every call a dependency
/// edge. The scope's coverage/leaf distinction isn't carried over — a hand-edited call graph has
/// no analysis behind it.
struct CallGraphFreeformConversion: FreeformConversion {
    let context: FreeformConversionContext
    private let graph: CallGraph

    init(context: FreeformConversionContext, scope: CallGraphScope) {
        self.context = context
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
}
