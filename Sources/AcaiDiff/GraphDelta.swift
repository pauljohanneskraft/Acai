import AcaiDiagram

protocol IdentifiableGraphNode: Sendable {
    var id: String { get }
}

protocol WeightedGraphEdge: Sendable {
    var from: String { get }
    var to: String { get }
    var weight: Int { get }
}

extension WeightedGraphEdge {
    var diffKey: GraphElementDiff.EdgeKey { GraphElementDiff.EdgeKey(from: from, to: to) }
}

extension Sequence where Element: WeightedGraphEdge {
    var weightsByKey: [GraphElementDiff.EdgeKey: Int] {
        Dictionary(map { ($0.diffKey, $0.weight) }, uniquingKeysWith: { first, _ in first })
    }
}

/// The delta logic shared by `CallGraphDiff` and `PackageDiagramDiff`: merges both revisions into
/// one set of `nodes`/`edges` (new first, then old-only appended) and classifies each element's
/// status, so each per-diagram wrapper only re-assembles its concrete diagram type from the result.
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
