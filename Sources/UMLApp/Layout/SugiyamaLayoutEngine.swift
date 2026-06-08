import CoreGraphics
import UMLCore

/// Orchestrates a layered graph layout algorithm to produce clean, hierarchical
/// node positions for class diagrams.
///
/// For typical codebases where many types are unrelated by inheritance, this
/// engine groups types by directory, lays out each connected component
/// separately, then arranges the component clusters in a grid.
struct SugiyamaLayoutEngine: Sendable {

    struct NodeInput: Sendable {
        let id: String
        let size: CGSize
        /// Directory-based group for clustering unrelated types.
        let group: String?
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
    var groupSpacing: CGFloat = 120

    /// Runs the full layout pipeline:
    /// 1. Find connected components (using all edge types).
    /// 2. Within each component, run Sugiyama (layer -> order -> coordinate).
    /// 3. Arrange components in a grid, respecting directory grouping.
    func layout(nodes: [NodeInput], edges: [EdgeInput]) -> LayoutResult {
        guard !nodes.isEmpty else { return LayoutResult(positions: [:]) }

        let nodeMap = Dictionary(grouping: nodes) { $0.id }
            .compactMapValues(\.first)
        let nodeSizes = nodeMap.mapValues(\.size)

        // Build bidirectional adjacency from ALL edges.
        var adjacency: [String: Set<String>] = [:]
        for edge in edges {
            adjacency[edge.sourceID, default: []].insert(edge.targetID)
            adjacency[edge.targetID, default: []].insert(edge.sourceID)
        }

        // Find connected components.
        let components = findConnectedComponents(nodeIDs: nodes.map(\.id), adjacency: adjacency)

        // Layout each component separately, then arrange them in a grid.
        var componentLayouts: [(bounds: CGSize, positions: [String: CGPoint], group: String?)] = []

        for component in components {
            let componentNodes = Array(component)
            let componentEdges = edges.filter {
                component.contains($0.sourceID) && component.contains($0.targetID)
            }

            let positions: [String: CGPoint]
            if component.count == 1 {
                let id = componentNodes[0]
                let size = nodeSizes[id] ?? CGSize(width: 180, height: 80)
                positions = [id: CGPoint(x: size.width / 2, y: size.height / 2)]
            } else {
                positions = layoutComponent(
                    nodeIDs: componentNodes,
                    edges: componentEdges,
                    nodeSizes: nodeSizes,
                    adjacency: adjacency
                )
            }

            let bounds = computeBounds(positions: positions, nodeSizes: nodeSizes)
            let primaryGroup = primaryDirectoryGroup(for: component, nodeMap: nodeMap)
            componentLayouts.append((bounds: bounds, positions: positions, group: primaryGroup))
        }

        // Arrange components in a grid grouped by directory.
        let finalPositions = arrangeComponentsInGrid(componentLayouts, nodeSizes: nodeSizes)

        return LayoutResult(positions: finalPositions)
    }

    /// Hierarchically partitions nodes by their `group` key, treated as a `"/"`-separated
    /// path (e.g. a directory path `Sources/UMLCore/ClassDiagram`). Each path level is laid
    /// out as its own block and nested inside its parent, so a box drawn around any prefix
    /// wraps a contiguous, non-overlapping region. A single-component group (e.g. a product
    /// name) collapses to one level — equivalent to the old flat per-group layout.
    ///
    /// `padding` leaves room inside each block for the group box border and its name tab;
    /// because it is applied at every level, deeper groups nest visibly inside shallower ones.
    func layoutByGroup(nodes: [NodeInput], edges: [EdgeInput], depth: Int = 0, padding: CGFloat = 32) -> LayoutResult {
        guard !nodes.isEmpty else { return LayoutResult(positions: [:]) }
        let nodeSizes = Dictionary(nodes.map { ($0.id, $0.size) }, uniquingKeysWith: { first, _ in first })

        func components(_ node: NodeInput) -> [String] {
            (node.group ?? "").split(separator: "/").map(String.init)
        }
        func intraEdges(_ groupNodes: [NodeInput]) -> [EdgeInput] {
            let ids = Set(groupNodes.map(\.id))
            return edges.filter { ids.contains($0.sourceID) && ids.contains($0.targetID) }
        }

        var blocks: [(size: CGSize, positions: [String: CGPoint])] = []
        func addBlock(_ positions: [String: CGPoint]) {
            guard !positions.isEmpty else { return }
            let normalized = normalizeToOrigin(positions, nodeSizes: nodeSizes, padding: padding)
            let bounds = computeBounds(positions: normalized, nodeSizes: nodeSizes)
            blocks.append(
                (
                    size: CGSize(width: bounds.width + padding * 2, height: bounds.height + padding * 2),
                    positions: normalized
                ))
        }

        // Nodes whose path ends at this level are laid out directly (no deeper box); the
        // rest recurse, grouped by their next path component (name-sorted for stable order).
        let direct = nodes.filter { components($0).count <= depth }
        if !direct.isEmpty {
            addBlock(layout(nodes: direct, edges: intraEdges(direct)).positions)
        }
        let nested = Dictionary(grouping: nodes.filter { components($0).count > depth }) { components($0)[depth] }
        for key in nested.keys.sorted() {
            let sub = nested[key]!
            addBlock(layoutByGroup(nodes: sub, edges: intraEdges(sub), depth: depth + 1, padding: padding).positions)
        }

        return LayoutResult(positions: placeBlocksInGrid(blocks))
    }

    /// Shifts a block's positions so its top-left node corner sits at `(padding, padding)`.
    private func normalizeToOrigin(
        _ positions: [String: CGPoint],
        nodeSizes: [String: CGSize],
        padding: CGFloat
    ) -> [String: CGPoint] {
        guard !positions.isEmpty else { return positions }
        let (minX, minY) = minCorner(of: positions, nodeSizes: nodeSizes)
        return positions.mapValues {
            CGPoint(x: $0.x - minX + padding, y: $0.y - minY + padding)
        }
    }

    // MARK: - Connected Components

    private func findConnectedComponents(
        nodeIDs: [String],
        adjacency: [String: Set<String>]
    ) -> [Set<String>] {
        var visited = Set<String>()
        var components: [Set<String>] = []

        for nodeID in nodeIDs {
            guard !visited.contains(nodeID) else { continue }
            var component = Set<String>()
            var queue = [nodeID]
            while !queue.isEmpty {
                let current = queue.removeFirst()
                guard !visited.contains(current) else { continue }
                visited.insert(current)
                component.insert(current)
                for neighbor in adjacency[current] ?? [] where !visited.contains(neighbor) {
                    queue.append(neighbor)
                }
            }
            components.append(component)
        }

        // Sort: larger components first.
        return components.sorted { $0.count > $1.count }
    }

    // MARK: - Layout Single Component (Sugiyama)

    private func layoutComponent(
        nodeIDs: [String],
        edges: [EdgeInput],
        nodeSizes: [String: CGSize],
        adjacency: [String: Set<String>]
    ) -> [String: CGPoint] {
        // Phase 1: Layer assignment.
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
        let componentAdj: [String: Set<String>] = adjacency.compactMapValues { neighbors in
            let filtered = neighbors.filter { Set(nodeIDs).contains($0) }
            return filtered.isEmpty ? nil : filtered
        }
        layers = CrossingMinimization.minimize(layers: layers, adjacency: componentAdj)

        // Phase 3: Coordinate assignment.
        return CoordinateAssignment.assign(
            layers: layers,
            nodeSizes: nodeSizes,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing,
            adjacency: componentAdj
        )
    }

    // MARK: - Arrange Components in Grid

    private func arrangeComponentsInGrid(
        _ components: [(bounds: CGSize, positions: [String: CGPoint], group: String?)],
        nodeSizes: [String: CGSize]
    ) -> [String: CGPoint] {
        guard !components.isEmpty else { return [:] }

        let groupedComponents = groupAndSort(components)
        let groupBlocks = buildGroupBlocks(groupedComponents, nodeSizes: nodeSizes)
        return placeBlocksInGrid(groupBlocks)
    }

    private func groupAndSort(
        _ components: [(bounds: CGSize, positions: [String: CGPoint], group: String?)]
    ) -> [(group: String, items: [(bounds: CGSize, positions: [String: CGPoint])])] {
        var grouped: [(group: String, items: [(bounds: CGSize, positions: [String: CGPoint])])] = []
        var seen: [String: Int] = [:]

        for comp in components {
            let group = comp.group ?? "_ungrouped"
            if let idx = seen[group] {
                grouped[idx].items.append((bounds: comp.bounds, positions: comp.positions))
            } else {
                seen[group] = grouped.count
                grouped.append((group: group, items: [(bounds: comp.bounds, positions: comp.positions)]))
            }
        }

        grouped.sort { a, b in
            a.items.reduce(0) { $0 + $1.positions.count } > b.items.reduce(0) { $0 + $1.positions.count }
        }
        return grouped
    }

    private func buildGroupBlocks(
        _ groupedComponents: [(group: String, items: [(bounds: CGSize, positions: [String: CGPoint])])],
        nodeSizes: [String: CGSize]
    ) -> [(size: CGSize, positions: [String: CGPoint])] {
        groupedComponents.map { group in
            var blockPositions: [String: CGPoint] = [:]
            var currentY: CGFloat = 0

            for (itemIdx, item) in group.items.enumerated() {
                let (minX, minY) = minCorner(of: item.positions, nodeSizes: nodeSizes)
                for (id, pos) in item.positions {
                    blockPositions[id] = CGPoint(x: pos.x - minX, y: pos.y - minY + currentY)
                }
                currentY += item.bounds.height + (itemIdx < group.items.count - 1 ? verticalSpacing * 0.6 : 0)
            }

            let blockBounds = computeBounds(positions: blockPositions, nodeSizes: nodeSizes)
            return (size: blockBounds, positions: blockPositions)
        }
    }

    private func placeBlocksInGrid(
        _ groupBlocks: [(size: CGSize, positions: [String: CGPoint])]
    ) -> [String: CGPoint] {
        var finalPositions: [String: CGPoint] = [:]
        let maxCols = max(1, Int(ceil(sqrt(Double(groupBlocks.count)))))

        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var colCount = 0

        for block in groupBlocks {
            if colCount >= maxCols {
                currentX = 0
                currentY += rowHeight + groupSpacing
                rowHeight = 0
                colCount = 0
            }

            for (id, pos) in block.positions {
                finalPositions[id] = CGPoint(x: pos.x + currentX, y: pos.y + currentY)
            }

            currentX += block.size.width + groupSpacing
            rowHeight = max(rowHeight, block.size.height)
            colCount += 1
        }

        return finalPositions
    }

    // MARK: - Helpers

    private func computeBounds(positions: [String: CGPoint], nodeSizes: [String: CGSize]) -> CGSize {
        guard !positions.isEmpty else { return .zero }
        let (minX, minY) = minCorner(of: positions, nodeSizes: nodeSizes)
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for (id, pos) in positions {
            let size = nodeSizes[id] ?? CGSize(width: 180, height: 80)
            maxX = max(maxX, pos.x + size.width / 2)
            maxY = max(maxY, pos.y + size.height / 2)
        }
        return CGSize(width: max(maxX - minX, 0), height: max(maxY - minY, 0))
    }

    private func minCorner(of positions: [String: CGPoint], nodeSizes: [String: CGSize]) -> (CGFloat, CGFloat) {
        var minX: CGFloat = .greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        for (id, pos) in positions {
            let size = nodeSizes[id] ?? CGSize(width: 180, height: 80)
            minX = min(minX, pos.x - size.width / 2)
            minY = min(minY, pos.y - size.height / 2)
        }
        return (minX, minY)
    }

    private func primaryDirectoryGroup(for component: Set<String>, nodeMap: [String: NodeInput]) -> String? {
        var groupCounts: [String: Int] = [:]
        for id in component {
            if let group = nodeMap[id]?.group {
                groupCounts[group, default: 0] += 1
            }
        }
        return groupCounts.max(by: { $0.value < $1.value })?.key
    }
}
