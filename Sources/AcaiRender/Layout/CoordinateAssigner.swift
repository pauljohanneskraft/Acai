import CoreGraphics

/// Phase 3 of Sugiyama layout: converts layer assignments and ordering into concrete (x, y) centre
/// coordinates.
struct CoordinateAssigner {
    let nodeSizes: [String: CGSize]
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    /// Bidirectional adjacency, used by the straightening refinement passes.
    let adjacency: [String: Set<String>]

    func assign(layers: [[String]]) -> [String: CGPoint] {
        guard !layers.isEmpty else { return [:] }
        var positions: [String: CGPoint] = [:]

        var layerYCenters: [CGFloat] = []
        var currentY: CGFloat = 0
        for layer in layers {
            let maxHeight = layer.compactMap { nodeSizes[$0]?.height }.max() ?? 80
            layerYCenters.append(currentY + maxHeight / 2)
            currentY += maxHeight + verticalSpacing
        }

        var layerWidths: [CGFloat] = []
        for (layerIndex, layer) in layers.enumerated() {
            var currentX: CGFloat = 0
            for nodeID in layer {
                let size = nodeSizes[nodeID] ?? CGSize(width: 180, height: 80)
                positions[nodeID] = CGPoint(x: currentX + size.width / 2, y: layerYCenters[layerIndex])
                currentX += size.width + horizontalSpacing
            }
            layerWidths.append(max(currentX - horizontalSpacing, 0))
        }

        let maxWidth = layerWidths.max() ?? 0
        for (layerIndex, layer) in layers.enumerated() {
            let offsetX = (maxWidth - layerWidths[layerIndex]) / 2
            for nodeID in layer { positions[nodeID]?.x += offsetX }
        }

        for _ in 0..<8 { refinementPass(layers: layers, positions: &positions) }
        return positions
    }

    private func refinementPass(layers: [[String]], positions: inout [String: CGPoint]) {
        for layer in layers {
            for nodeID in layer {
                guard let currentPos = positions[nodeID] else { continue }
                let neighborXValues = (adjacency[nodeID] ?? []).compactMap { positions[$0]?.x }
                guard !neighborXValues.isEmpty else { continue }
                let avgX = neighborXValues.reduce(0, +) / CGFloat(neighborXValues.count)
                positions[nodeID]?.x += (avgX - currentPos.x) * 0.3  // damping factor
            }
            resolveOverlaps(layer: layer, positions: &positions)
        }
    }

    private func resolveOverlaps(layer: [String], positions: inout [String: CGPoint]) {
        let sorted = layer.sorted { (positions[$0]?.x ?? 0) < (positions[$1]?.x ?? 0) }
        guard sorted.count > 1 else { return }
        for i in 1..<sorted.count {
            guard let prevPos = positions[sorted[i - 1]], let currPos = positions[sorted[i]] else { continue }
            let prevHalfWidth = (nodeSizes[sorted[i - 1]]?.width ?? 180) / 2
            let currHalfWidth = (nodeSizes[sorted[i]]?.width ?? 180) / 2
            let minX = prevPos.x + prevHalfWidth + horizontalSpacing + currHalfWidth
            if currPos.x < minX { positions[sorted[i]]?.x = minX }
        }
    }
}
