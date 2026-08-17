/// Phase 2 of Sugiyama layout: orders nodes within each layer to minimize edge crossings between
/// adjacent layers using the barycenter heuristic.
struct CrossingMinimizer {
    let adjacency: [String: Set<String>]
    /// Number of sweep passes (alternating top-down and bottom-up).
    var iterations = 24

    func minimize(_ layers: [[String]]) -> [[String]] {
        guard layers.count > 1 else { return layers }
        var result = layers

        func positionLookup() -> [String: Int] {
            var lookup: [String: Int] = [:]
            for layer in result {
                for (index, nodeID) in layer.enumerated() { lookup[nodeID] = index }
            }
            return lookup
        }

        for iteration in 0..<iterations {
            let positions = positionLookup()
            if iteration.isMultiple(of: 2) {
                // Top-down sweep: fix upper layers, reorder lower layers.
                for layerIndex in 1..<result.count {
                    result[layerIndex] = reorder(
                        result[layerIndex], referenceLayer: result[layerIndex - 1], referencePositions: positions)
                }
            } else {
                // Bottom-up sweep: fix lower layers, reorder upper layers.
                for layerIndex in (0..<result.count - 1).reversed() {
                    result[layerIndex] = reorder(
                        result[layerIndex], referenceLayer: result[layerIndex + 1], referencePositions: positions)
                }
            }
        }
        return result
    }

    private func reorder(
        _ layer: [String], referenceLayer: [String], referencePositions: [String: Int]
    ) -> [String] {
        let refSet = Set(referenceLayer)
        return layer.sorted { lhs, rhs in
            barycenter(of: lhs, in: refSet, positions: referencePositions)
                < barycenter(of: rhs, in: refSet, positions: referencePositions)
        }
    }

    private func barycenter(of nodeID: String, in referenceSet: Set<String>, positions: [String: Int]) -> Double {
        let neighbors = (adjacency[nodeID] ?? []).filter { referenceSet.contains($0) }
        guard !neighbors.isEmpty else { return Double.greatestFiniteMagnitude }
        let sum = neighbors.compactMap { positions[$0] }.reduce(0, +)
        return Double(sum) / Double(neighbors.count)
    }
}
