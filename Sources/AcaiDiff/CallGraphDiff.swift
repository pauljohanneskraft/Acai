import AcaiDiagram

extension CallGraph.Node: IdentifiableGraphNode {}
extension CallGraph.Edge: WeightedGraphEdge {}

/// The delta between two `CallGraph` revisions. Method nodes are identified by `id`
/// (`Type.method` / `function`); call edges by `(from, to)`, with a call-count change reported as
/// *changed*. The `union` merges both revisions so a renderer can draw every node/edge and tint
/// each by `status(ofNode:)` / `status(ofEdgeFrom:to:)`.
public struct CallGraphDiff: Sendable {
    public let union: CallGraph
    private let delta: GraphDelta<CallGraph.Node, CallGraph.Edge>

    public init(old: CallGraph, new: CallGraph) {
        delta = GraphDelta(oldNodes: old.nodes, newNodes: new.nodes, oldEdges: old.edges, newEdges: new.edges)
        union = CallGraph(
            title: new.title ?? old.title, nodes: delta.nodes, edges: delta.edges, coverage: new.coverage)
    }

    public func status(ofNode id: String) -> DeltaStatus { delta.status(ofNode: id) }
    public func status(ofEdgeFrom from: String, to: String) -> DeltaStatus {
        delta.status(ofEdgeFrom: from, to: to)
    }
}
