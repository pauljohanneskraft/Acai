import UMLDiagram

/// The delta between two `CallGraph` revisions. Method nodes are identified by `id`
/// (`Type.method` / `function`); call edges by `(from, to)`, with a call-count change reported as
/// *changed*. The `union` merges both revisions so a renderer can draw every node/edge and tint
/// each by `status(ofNode:)` / `status(ofEdgeFrom:to:)`.
public struct CallGraphDiff: Sendable {
    public let union: CallGraph
    private let elements: GraphElementDiff

    public init(old: CallGraph, new: CallGraph) {
        elements = GraphElementDiff(
            oldNodeIDs: old.nodes.map(\.id),
            newNodeIDs: new.nodes.map(\.id),
            oldEdges: old.edges.weightsByKey,
            newEdges: new.edges.weightsByKey
        )

        var nodes = new.nodes
        let seenNodes = Set(new.nodes.map(\.id))
        nodes += old.nodes.filter { !seenNodes.contains($0.id) }

        var edges = new.edges
        let seenEdges = Set(new.edges.map(\.diffKey))
        edges += old.edges.filter { !seenEdges.contains($0.diffKey) }

        self.union = CallGraph(title: new.title ?? old.title, nodes: nodes, edges: edges, coverage: new.coverage)
    }

    public func status(ofNode id: String) -> DeltaStatus { elements.status(ofNode: id) }
    public func status(ofEdgeFrom from: String, to: String) -> DeltaStatus {
        elements.status(of: GraphElementDiff.EdgeKey(from: from, to: to))
    }
}

extension CallGraph.Edge {
    var diffKey: GraphElementDiff.EdgeKey { GraphElementDiff.EdgeKey(from: from, to: to) }
}

extension Sequence where Element == CallGraph.Edge {
    /// These edges indexed by their diff key → weight (first weight wins on a duplicate key).
    var weightsByKey: [GraphElementDiff.EdgeKey: Int] {
        Dictionary(map { ($0.diffKey, $0.weight) }, uniquingKeysWith: { first, _ in first })
    }
}
