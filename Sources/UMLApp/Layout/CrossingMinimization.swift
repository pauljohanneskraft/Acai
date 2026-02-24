/// Phase 2 of Sugiyama layout: orders nodes within each layer to minimize
/// edge crossings between adjacent layers using the barycenter heuristic.
enum CrossingMinimization {

    /// Reorders nodes within layers to minimize edge crossings.
    /// - Parameters:
    ///   - layers: Ordered layers, each containing node IDs.
    ///   - adjacency: For each node, the set of nodes it is connected to (both directions).
    ///   - iterations: Number of sweep passes (default 24, alternating top-down and bottom-up).
    /// - Returns: Reordered layers.
    static func minimize(
        layers: [[String]],
        adjacency: [String: Set<String>],
        iterations: Int = 24
    ) -> [[String]] {
        guard layers.count > 1 else { return layers }

        var result = layers

        // Build position lookup: nodeID → position within its layer
        func positionLookup() -> [String: Int] {
            var lookup: [String: Int] = [:]
            for layer in result {
                for (index, nodeID) in layer.enumerated() {
                    lookup[nodeID] = index
                }
            }
            return lookup
        }

        for iteration in 0..<iterations {
            let positions = positionLookup()

            if iteration.isMultiple(of: 2) {
                // Top-down sweep: fix upper layers, reorder lower layers
                for layerIndex in 1..<result.count {
                    result[layerIndex] = reorderLayer(
                        result[layerIndex],
                        referenceLayer: result[layerIndex - 1],
                        adjacency: adjacency,
                        referencePositions: positions
                    )
                }
            } else {
                // Bottom-up sweep: fix lower layers, reorder upper layers
                for layerIndex in (0..<result.count - 1).reversed() {
                    result[layerIndex] = reorderLayer(
                        result[layerIndex],
                        referenceLayer: result[layerIndex + 1],
                        adjacency: adjacency,
                        referencePositions: positions
                    )
                }
            }
        }

        return result
    }

    /// Reorders a single layer based on the barycenter of connected nodes in the reference layer.
    private static func reorderLayer(
        _ layer: [String],
        referenceLayer: [String],
        adjacency: [String: Set<String>],
        referencePositions: [String: Int]
    ) -> [String] {
        let refSet = Set(referenceLayer)

        let sorted = layer.sorted { a, b in
            let baryA = barycenter(of: a, in: refSet, adjacency: adjacency, positions: referencePositions)
            let baryB = barycenter(of: b, in: refSet, adjacency: adjacency, positions: referencePositions)
            return baryA < baryB
        }

        return sorted
    }

    /// Computes the barycenter (average position) of a node's neighbors in the reference layer.
    private static func barycenter(
        of nodeID: String,
        in referenceSet: Set<String>,
        adjacency: [String: Set<String>],
        positions: [String: Int]
    ) -> Double {
        let neighbors = (adjacency[nodeID] ?? []).filter { referenceSet.contains($0) }
        guard !neighbors.isEmpty else { return Double.greatestFiniteMagnitude }

        let sum = neighbors.compactMap { positions[$0] }.reduce(0, +)
        return Double(sum) / Double(neighbors.count)
    }
}
