import CoreGraphics
import Foundation
import AcaiDiagram

/// Shared Sugiyama-backed placement for the directed-graph diagram kinds (call graph, package,
/// state). The per-kind models supply node sizes and edges and build their own typed
/// `NodeFrame`/`EdgeLayout` arrays from `framesByID`.
struct DirectedGraphLayout {
    let framesByID: [String: CGRect]
    /// At least 1×1 so an empty graph still has a valid canvas.
    let contentSize: CGSize

    /// `edges` must already be oriented for `LayerAssignment` (which lifts edge *targets* toward
    /// the top) — callers reverse where needed. `groups` keys a node id to its group path, laying
    /// each group out contiguously; `margin` surrounds the nodes with room for the group boxes.
    /// `positionOverrides` are node centres in the coordinates of the returned frames.
    init(
        nodeSizes: [(id: String, size: CGSize)],
        edges: [(from: String, to: String)],
        positionOverrides: [String: CGPoint],
        groups: [String: String] = [:],
        margin: CGFloat = 0
    ) {
        let sizeByID = Dictionary(nodeSizes.map { ($0.id, $0.size) }, uniquingKeysWith: { first, _ in first })

        let inputs = nodeSizes.map {
            SugiyamaLayoutEngine.NodeInput(id: $0.id, size: $0.size, group: groups[$0.id])
        }
        let edgeInputs = edges.map {
            SugiyamaLayoutEngine.EdgeInput(sourceID: $0.from, targetID: $0.to, kind: .inheritance)
        }
        let engine = SugiyamaLayoutEngine()
        var positions: [String: CGPoint]
        if groups.isEmpty {
            positions = engine.layout(nodes: inputs, edges: edgeInputs).positions
        } else {
            // The grouped engine pads its output, so it is moved to the origin before an override
            // (recorded against the unpadded frames) joins it.
            let padded = engine.layoutByGroup(nodes: inputs, edges: edgeInputs).positions
            let corner = padded.minCorner(sizes: sizeByID)
            positions = padded.mapValues { CGPoint(x: $0.x - corner.x, y: $0.y - corner.y) }
        }
        for (id, point) in positionOverrides {
            positions[id] = CGPoint(x: point.x - margin, y: point.y - margin)
        }

        let corner = positions.minCorner(sizes: sizeByID)
        var frames: [String: CGRect] = [:]
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for (id, size) in sizeByID {
            let center = positions[id] ?? .zero
            let rect = CGRect(
                x: center.x - size.width / 2 - corner.x + margin,
                y: center.y - size.height / 2 - corner.y + margin,
                width: size.width,
                height: size.height
            )
            frames[id] = rect
            maxX = max(maxX, rect.maxX)
            maxY = max(maxY, rect.maxY)
        }

        framesByID = frames
        contentSize = CGSize(width: max(maxX + margin, 1), height: max(maxY + margin, 1))
    }
}

private extension Dictionary where Key == String, Value == CGPoint {
    /// The top-left corner of the nodes centred at these positions; the origin when there are none.
    func minCorner(sizes: [String: CGSize]) -> CGPoint {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        for (id, size) in sizes {
            let center = self[id] ?? .zero
            minX = Swift.min(minX, center.x - size.width / 2)
            minY = Swift.min(minY, center.y - size.height / 2)
        }
        if minX == .greatestFiniteMagnitude { minX = 0 }
        if minY == .greatestFiniteMagnitude { minY = 0 }
        return CGPoint(x: minX, y: minY)
    }
}
