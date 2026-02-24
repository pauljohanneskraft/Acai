import CoreGraphics
import UMLCore

/// Orchestrates the Sugiyama layered graph layout algorithm to produce
/// clean, hierarchical node positions for class diagrams.
struct SugiyamaLayoutEngine: Sendable {

    struct NodeInput: Sendable {
        let id: String
        let size: CGSize
    }

    struct EdgeInput: Sendable {
        let sourceID: String
        let targetID: String
        let kind: Relationship.Kind
    }

    struct LayoutResult: Sendable {
        var positions: [String: CGPoint]
    }

    var horizontalSpacing: CGFloat = 50
    var verticalSpacing: CGFloat = 80

    /// Runs the full Sugiyama layout pipeline and returns center positions for each node.
    func layout(nodes: [NodeInput], edges: [EdgeInput]) -> LayoutResult {
        guard !nodes.isEmpty else { return LayoutResult(positions: [:]) }

        let nodeIDs = nodes.map(\.id)
        let nodeSizes = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.size) })

        // Phase 1: Layer assignment based on inheritance/conformance hierarchy.
        let layerMap = LayerAssignment.assign(
            nodeIDs: nodeIDs,
            edges: edges.map { (source: $0.sourceID, target: $0.targetID, kind: $0.kind) }
        )

        // Group nodes by layer.
        var layerBuckets: [Int: [String]] = [:]
        for (nodeID, layer) in layerMap {
            layerBuckets[layer, default: []].append(nodeID)
        }
        let sortedLayerIndices = layerBuckets.keys.sorted()
        var layers = sortedLayerIndices.map { layerBuckets[$0]! }

        // Phase 2: Crossing minimization.
        // Build bidirectional adjacency from all edges.
        var adjacency: [String: Set<String>] = [:]
        for edge in edges {
            adjacency[edge.sourceID, default: []].insert(edge.targetID)
            adjacency[edge.targetID, default: []].insert(edge.sourceID)
        }

        layers = CrossingMinimization.minimize(layers: layers, adjacency: adjacency)

        // Phase 3: Coordinate assignment.
        let positions = CoordinateAssignment.assign(
            layers: layers,
            nodeSizes: nodeSizes,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing,
            adjacency: adjacency
        )

        return LayoutResult(positions: positions)
    }
}
