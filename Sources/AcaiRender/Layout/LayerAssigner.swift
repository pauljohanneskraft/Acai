import AcaiCore

/// Phase 1 of Sugiyama layout: assigns each node to a vertical layer based on the hierarchy defined
/// by inheritance/conformance edges. When many nodes have no hierarchy edges (common in typical
/// codebases), they are spread across multiple rows rather than crammed into a single layer.
struct LayerAssigner {
    let nodeIDs: [String]
    let edges: [(source: String, target: String, kind: Relationship.Kind)]
    var hierarchyKinds: Set<Relationship.Kind> = [.inheritance, .conformance]
    var maxNodesPerRow = 5

    /// Assigns nodes to integer layers (0 = topmost).
    func assignment() -> [String: Int] {
        let nodeSet = Set(nodeIDs)

        // In UML, source inherits from / conforms to target, so target is the parent.
        var childrenOf: [String: [String]] = [:]
        var parentsOf: [String: [String]] = [:]
        for edge in edges where hierarchyKinds.contains(edge.kind) {
            guard nodeSet.contains(edge.source), nodeSet.contains(edge.target) else { continue }
            childrenOf[edge.target, default: []].append(edge.source)
            parentsOf[edge.source, default: []].append(edge.target)
        }

        let roots = nodeIDs.filter { (parentsOf[$0] ?? []).isEmpty && !(childrenOf[$0] ?? []).isEmpty }
        var layers: [String: Int] = [:]
        var queue: [String] = roots
        for root in roots { layers[root] = 0 }

        var visited = Set<String>()
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard !visited.contains(current) else { continue }
            visited.insert(current)
            let currentLayer = layers[current] ?? 0
            for child in childrenOf[current] ?? [] {
                let proposedLayer = currentLayer + 1
                if proposedLayer > (layers[child] ?? 0) { layers[child] = proposedLayer }
                if !visited.contains(child) { queue.append(child) }
            }
        }

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
