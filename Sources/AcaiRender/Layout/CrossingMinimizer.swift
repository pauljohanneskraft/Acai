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

        for iteration in 0..<effectiveIterations(forLayerCount: layers.count) {
            let positions = positionLookup()
            let beforeSweep = result
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
            // A sweep that reordered nothing has reached a fixed point: every later sweep would
            // re-sort the same already-sorted layers into themselves, so stopping here changes
            // nothing about the result, only how much redundant work it takes to reach it.
            if result == beforeSweep { break }
        }
        return result
    }

    /// The 24-sweep default is cheap for the layer counts a class/package diagram normally has, but a
    /// pathological graph that never reaches the fixed point above (oscillating between two barycenter
    /// orderings) would otherwise run all 24 full sweeps over every layer. Scaling the ceiling down as
    /// layers grow bounds that worst case without touching the (much smaller) layer counts every
    /// `Examples/` golden actually has, so their output is unaffected.
    private func effectiveIterations(forLayerCount layerCount: Int) -> Int {
        guard layerCount > 50 else { return iterations }
        return max(6, iterations * 50 / layerCount)
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
