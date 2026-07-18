import CoreGraphics
import Foundation
import AcaiDiagram

/// Shared Sugiyama-backed placement for the directed-graph diagram kinds (call graph, package,
/// state). Runs the layout engine, applies user position overrides, normalizes the result so the
/// content's top-left sits at the origin, and exposes node frames keyed by id plus the overall
/// content size. The per-kind models supply node sizes and edges and build their own typed
/// `NodeFrame`/`EdgeLayout` arrays from `framesByID`.
struct DirectedGraphLayout {
    /// Laid-out frame per node id (every supplied node gets a frame).
    let framesByID: [String: CGRect]
    /// The bounding size of all frames (at least 1×1 so an empty graph still has a valid canvas).
    let contentSize: CGSize

    /// - Parameters:
    ///   - nodeSizes: every node's id and rendered size.
    ///   - edges: directed edges already oriented for `LayerAssignment` (which lifts edge *targets*
    ///     toward the top), so callers reverse where needed.
    ///   - positionOverrides: node-id → centre, taking precedence over computed positions (restores
    ///     user drags).
    init(
        nodeSizes: [(id: String, size: CGSize)],
        edges: [(from: String, to: String)],
        positionOverrides: [String: CGPoint]
    ) {
        let sizeByID = Dictionary(nodeSizes.map { ($0.id, $0.size) }, uniquingKeysWith: { first, _ in first })

        let inputs = nodeSizes.map {
            SugiyamaLayoutEngine.NodeInput(id: $0.id, size: $0.size, group: nil)
        }
        let edgeInputs = edges.map {
            SugiyamaLayoutEngine.EdgeInput(sourceID: $0.from, targetID: $0.to, kind: .inheritance)
        }
        var positions = SugiyamaLayoutEngine().layout(nodes: inputs, edges: edgeInputs).positions
        for (id, point) in positionOverrides {
            positions[id] = point
        }

        // Normalize so the content's top-left corner sits at the origin.
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        for (id, size) in sizeByID {
            let center = positions[id] ?? .zero
            minX = min(minX, center.x - size.width / 2)
            minY = min(minY, center.y - size.height / 2)
        }
        if minX == .greatestFiniteMagnitude { minX = 0 }
        if minY == .greatestFiniteMagnitude { minY = 0 }

        var frames: [String: CGRect] = [:]
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for (id, size) in sizeByID {
            let center = positions[id] ?? .zero
            let rect = CGRect(
                x: center.x - size.width / 2 - minX,
                y: center.y - size.height / 2 - minY,
                width: size.width,
                height: size.height
            )
            frames[id] = rect
            maxX = max(maxX, rect.maxX)
            maxY = max(maxY, rect.maxY)
        }

        framesByID = frames
        contentSize = CGSize(width: max(maxX, 1), height: max(maxY, 1))
    }
}
