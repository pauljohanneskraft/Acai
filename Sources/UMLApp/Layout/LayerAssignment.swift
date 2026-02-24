import UMLCore

/// Phase 1 of Sugiyama layout: assigns each node to a vertical layer based on
/// the hierarchy defined by inheritance/conformance edges.
enum LayerAssignment {

    /// Assigns nodes to integer layers (0 = topmost).
    /// - Parameters:
    ///   - nodeIDs: All node identifiers in the graph.
    ///   - edges: Directed edges as (source, target) pairs.
    ///   - hierarchyKinds: Relationship kinds that define parent-child layering
    ///     (typically inheritance and conformance). Edges where `target` is the
    ///     parent are used: source (child) goes below target (parent).
    ///   - allEdges: All edges including non-hierarchy ones, with their kinds.
    /// - Returns: A mapping from node ID to layer index.
    static func assign(
        nodeIDs: [String],
        edges: [(source: String, target: String, kind: Relationship.Kind)],
        hierarchyKinds: Set<Relationship.Kind> = [.inheritance, .conformance]
    ) -> [String: Int] {
        let nodeSet = Set(nodeIDs)

        // Build adjacency: parent → [children] using hierarchy edges only.
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

        // First pass: assign roots to layer 0 and BFS downward.
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

        // Assign disconnected nodes (no hierarchy edges at all) to a separate layer.
        let maxLayer = layers.values.max() ?? 0
        let disconnected = nodeIDs.filter { layers[$0] == nil }

        if !disconnected.isEmpty {
            // Place disconnected nodes at the bottom, grouped in their own layer.
            let disconnectedLayer = maxLayer + 1
            for nodeID in disconnected {
                layers[nodeID] = disconnectedLayer
            }
        }

        return layers
    }
}
