import CoreGraphics

/// Phase 3 of Sugiyama layout: converts layer assignments and ordering into
/// concrete (x, y) coordinates for each node.
enum CoordinateAssignment {

    /// Assigns coordinates to nodes based on their layer and within-layer ordering.
    /// - Parameters:
    ///   - layers: Ordered layers from crossing minimization, each containing node IDs.
    ///   - nodeSizes: Size of each node (keyed by node ID).
    ///   - horizontalSpacing: Horizontal gap between adjacent nodes in the same layer.
    ///   - verticalSpacing: Vertical gap between layers.
    ///   - adjacency: Bidirectional adjacency for refinement.
    /// - Returns: Center positions for each node.
    static func assign(
        layers: [[String]],
        nodeSizes: [String: CGSize],
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat,
        adjacency: [String: Set<String>]
    ) -> [String: CGPoint] {
        guard !layers.isEmpty else { return [:] }

        var positions: [String: CGPoint] = [:]

        // Step 1: Compute Y coordinates (center of each layer).
        var layerYCenters: [CGFloat] = []
        var currentY: CGFloat = 0
        for layer in layers {
            let maxHeight = layer.compactMap { nodeSizes[$0]?.height }.max() ?? 80
            let centerY = currentY + maxHeight / 2
            layerYCenters.append(centerY)
            currentY += maxHeight + verticalSpacing
        }

        // Step 2: Compute X coordinates within each layer.
        var layerWidths: [CGFloat] = []
        for (layerIndex, layer) in layers.enumerated() {
            var currentX: CGFloat = 0
            for nodeID in layer {
                let size = nodeSizes[nodeID] ?? CGSize(width: 180, height: 80)
                let centerX = currentX + size.width / 2
                positions[nodeID] = CGPoint(x: centerX, y: layerYCenters[layerIndex])
                currentX += size.width + horizontalSpacing
            }
            let totalWidth = currentX - horizontalSpacing
            layerWidths.append(max(totalWidth, 0))
        }

        // Step 3: Center all layers relative to the widest layer.
        let maxWidth = layerWidths.max() ?? 0
        for (layerIndex, layer) in layers.enumerated() {
            let layerWidth = layerWidths[layerIndex]
            let offsetX = (maxWidth - layerWidth) / 2
            for nodeID in layer {
                positions[nodeID]?.x += offsetX
            }
        }

        // Step 4: Refinement — nudge nodes toward connected neighbors to straighten edges.
        for _ in 0..<8 {
            refinementPass(
                layers: layers,
                positions: &positions,
                nodeSizes: nodeSizes,
                adjacency: adjacency,
                horizontalSpacing: horizontalSpacing
            )
        }

        return positions
    }

    /// A single refinement pass that shifts each node toward the average X of its connected
    /// neighbors in adjacent layers, while preventing overlap.
    private static func refinementPass(
        layers: [[String]],
        positions: inout [String: CGPoint],
        nodeSizes: [String: CGSize],
        adjacency: [String: Set<String>],
        horizontalSpacing: CGFloat
    ) {
        for layer in layers {
            for nodeID in layer {
                guard let currentPos = positions[nodeID] else { continue }
                let neighbors = adjacency[nodeID] ?? []
                let neighborXValues = neighbors.compactMap { positions[$0]?.x }
                guard !neighborXValues.isEmpty else { continue }

                let avgX = neighborXValues.reduce(0, +) / CGFloat(neighborXValues.count)
                let delta = (avgX - currentPos.x) * 0.3 // damping factor
                positions[nodeID]?.x += delta
            }

            // Resolve overlaps within the layer after shifting.
            resolveOverlaps(
                layer: layer,
                positions: &positions,
                nodeSizes: nodeSizes,
                horizontalSpacing: horizontalSpacing
            )
        }
    }

    /// Ensures nodes in a layer don't overlap after position adjustments.
    private static func resolveOverlaps(
        layer: [String],
        positions: inout [String: CGPoint],
        nodeSizes: [String: CGSize],
        horizontalSpacing: CGFloat
    ) {
        // Sort by current X position.
        let sorted = layer.sorted { (positions[$0]?.x ?? 0) < (positions[$1]?.x ?? 0) }

        for i in 1..<sorted.count {
            let prevID = sorted[i - 1]
            let currID = sorted[i]
            guard let prevPos = positions[prevID], let currPos = positions[currID] else { continue }
            let prevHalfWidth = (nodeSizes[prevID]?.width ?? 180) / 2
            let currHalfWidth = (nodeSizes[currID]?.width ?? 180) / 2
            let minX = prevPos.x + prevHalfWidth + horizontalSpacing + currHalfWidth
            if currPos.x < minX {
                positions[currID]?.x = minX
            }
        }
    }
}
