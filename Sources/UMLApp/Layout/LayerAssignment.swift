import UMLCore

/// Phase 1 of Sugiyama layout: assigns each node to a vertical layer based on
/// the hierarchy defined by inheritance/conformance edges.
///
/// When many nodes have no hierarchy edges (common in typical codebases),
/// they are spread across multiple rows in a grid pattern rather than
/// being crammed into a single layer.
enum LayerAssignment {

    /// Maximum number of nodes per layer for disconnected nodes.
    /// Keeps the diagram from becoming a single wide row.
    private static let maxNodesPerRow = 5

    /// Assigns nodes to integer layers (0 = topmost).
    static func assign(
        nodeIDs: [String],
        edges: [(source: String, target: String, kind: Relationship.Kind)],
        hierarchyKinds: Set<Relationship.Kind> = [.inheritance, .conformance]
    ) -> [String: Int] {
        let nodeSet = Set(nodeIDs)

        // Build adjacency: parent -> [children] using hierarchy edges only.
        // In UML, source inherits from / conforms to target, so target is the parent.
        var childrenOf: [String: [String]] = [:]
        var parentsOf: [String: [String]] = [:]

        for edge in edges where hierarchyKinds.contains(edge.kind) {
            guard nodeSet.contains(edge.source), nodeSet.contains(edge.target) else { continue }
            childrenOf[edge.target, default: []].append(edge.source)
            parentsOf[edge.source, default: []].append(edge.target)
        }

        // Find root nodes (no parents in the hierarchy).
        let roots = nodeIDs.filter { (parentsOf[$0] ?? []).isEmpty && !(childrenOf[$0] ?? []).isEmpty }

        // BFS from roots to assign layers.
        var layers: [String: Int] = [:]

        var queue: [String] = roots
        for root in roots {
            layers[root] = 0
        }

        var visited = Set<String>()
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard !visited.contains(current) else { continue }
            visited.insert(current)

            let currentLayer = layers[current] ?? 0
            for child in childrenOf[current] ?? [] {
                let proposedLayer = currentLayer + 1
                if proposedLayer > (layers[child] ?? 0) {
                    layers[child] = proposedLayer
                }
                if !visited.contains(child) {
                    queue.append(child)
                }
            }
        }

        // Spread disconnected nodes across multiple rows instead of one.
        let maxHierarchyLayer = layers.values.max() ?? -1
        let disconnected = nodeIDs.filter { layers[$0] == nil }

        if !disconnected.isEmpty {
            let startLayer = maxHierarchyLayer + 1
            for (index, nodeID) in disconnected.enumerated() {
                layers[nodeID] = startLayer + index / maxNodesPerRow
            }
        }

        return layers
    }
}
