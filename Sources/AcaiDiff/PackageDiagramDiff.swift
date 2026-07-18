import AcaiDiagram

extension PackageDiagram.Node: IdentifiableGraphNode {}
extension PackageDiagram.Edge: WeightedGraphEdge {}

/// The delta between two `PackageDiagram` revisions. Module nodes are identified by `id`;
/// edges by `(from, to)`, with a weight change reported as *changed*. The `union` merges both
/// revisions so a renderer can draw every module/edge and tint each by `status(ofNode:)` /
/// `status(ofEdgeFrom:to:)`.
public struct PackageDiagramDiff: Sendable {
    public let union: PackageDiagram
    private let delta: GraphDelta<PackageDiagram.Node, PackageDiagram.Edge>

    public init(old: PackageDiagram, new: PackageDiagram) {
        delta = GraphDelta(oldNodes: old.nodes, newNodes: new.nodes, oldEdges: old.edges, newEdges: new.edges)
        union = PackageDiagram(title: new.title ?? old.title, nodes: delta.nodes, edges: delta.edges)
    }

    public func status(ofNode id: String) -> DeltaStatus { delta.status(ofNode: id) }
    public func status(ofEdgeFrom from: String, to: String) -> DeltaStatus {
        delta.status(ofEdgeFrom: from, to: to)
    }
}
