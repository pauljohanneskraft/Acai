import UMLDiagram

extension PackageDependencyDiagram.Node: IdentifiableGraphNode {}
extension PackageDependencyDiagram.Edge: WeightedGraphEdge {}

/// The delta between two `PackageDependencyDiagram` revisions. Module nodes are identified by `id`;
/// edges by `(from, to)`, with a weight change reported as *changed*. The `union` merges both
/// revisions so a renderer can draw every module/edge and tint each by `status(ofNode:)` /
/// `status(ofEdgeFrom:to:)`.
public struct PackageDiagramDiff: Sendable {
    public let union: PackageDependencyDiagram
    private let delta: GraphDelta<PackageDependencyDiagram.Node, PackageDependencyDiagram.Edge>

    public init(old: PackageDependencyDiagram, new: PackageDependencyDiagram) {
        delta = GraphDelta(oldNodes: old.nodes, newNodes: new.nodes, oldEdges: old.edges, newEdges: new.edges)
        union = PackageDependencyDiagram(title: new.title ?? old.title, nodes: delta.nodes, edges: delta.edges)
    }

    public func status(ofNode id: String) -> DeltaStatus { delta.status(ofNode: id) }
    public func status(ofEdgeFrom from: String, to: String) -> DeltaStatus {
        delta.status(ofEdgeFrom: from, to: to)
    }
}
