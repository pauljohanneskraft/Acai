import AcaiDiagram

/// A graph node identified by a canonical id.
protocol IdentifiableGraphNode: Sendable {
    var id: String { get }
}

/// A directed, weighted graph edge.
protocol WeightedGraphEdge: Sendable {
    var from: String { get }
    var to: String { get }
    var weight: Int { get }
}

extension WeightedGraphEdge {
    /// This edge's identity for diffing — `(from, to)`, weight excluded.
    var diffKey: GraphElementDiff.EdgeKey { GraphElementDiff.EdgeKey(from: from, to: to) }
}

extension Sequence where Element: WeightedGraphEdge {
    /// These edges indexed by their diff key → weight (first weight wins on a duplicate key).
    var weightsByKey: [GraphElementDiff.EdgeKey: Int] {
        Dictionary(map { ($0.diffKey, $0.weight) }, uniquingKeysWith: { first, _ in first })
    }
}

/// The shared delta of the two "id-node + `(from, to)`-edge" diagram diffs (call graph, package
/// dependency). Merges both revisions into one set of `nodes`/`edges` (new first, then old-only
/// appended) and classifies each element's status — the logic `CallGraphDiff`/`PackageDiagramDiff`
/// would otherwise duplicate. The per-diagram wrapper only re-assembles its concrete diagram type
/// from `nodes`/`edges` (e.g. carrying a call graph's coverage).
struct GraphDelta<Node: IdentifiableGraphNode, Edge: WeightedGraphEdge>: Sendable {
    let nodes: [Node]
    let edges: [Edge]
    private let elements: GraphElementDiff

    init(oldNodes: [Node], newNodes: [Node], oldEdges: [Edge], newEdges: [Edge]) {
        elements = GraphElementDiff(
            oldNodeIDs: oldNodes.map(\.id),
            newNodeIDs: newNodes.map(\.id),
            oldEdges: oldEdges.weightsByKey,
            newEdges: newEdges.weightsByKey
        )

        var nodes = newNodes
        let seenNodes = Set(newNodes.map(\.id))
        nodes += oldNodes.filter { !seenNodes.contains($0.id) }
        self.nodes = nodes

        var edges = newEdges
        let seenEdges = Set(newEdges.map(\.diffKey))
        edges += oldEdges.filter { !seenEdges.contains($0.diffKey) }
        self.edges = edges
    }

    func status(ofNode id: String) -> DeltaStatus { elements.status(ofNode: id) }
    func status(ofEdgeFrom from: String, to: String) -> DeltaStatus {
        elements.status(of: GraphElementDiff.EdgeKey(from: from, to: to))
    }
}
