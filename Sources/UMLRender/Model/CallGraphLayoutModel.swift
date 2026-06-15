import CoreGraphics
import Foundation
import UMLCore
import UMLDiagram

/// Computes node frames and edge routes for a `CallGraph`.
///
/// Methods and their calls form a directed graph, so layout delegates to the shared
/// `SugiyamaLayoutEngine` — the same approach `PackageLayoutModel` and `StateLayoutModel` use.
/// Each call is fed as an `.inheritance` edge so `LayerAssignment` stacks the graph into clean
/// caller/callee layers.
public struct CallGraphLayoutModel: Sendable {

    public struct NodeFrame: Identifiable, Sendable {
        public let id: String
        public let node: CallGraph.Node
        public let rect: CGRect
    }

    public struct EdgeLayout: Identifiable, Sendable {
        public let id: Int
        public let from: String
        public let to: String
        /// Call multiplicity — drives line thickness (not a text label).
        public let weight: Int
    }

    public let nodes: [NodeFrame]
    public let edges: [EdgeLayout]
    public let contentSize: CGSize

    private let framesByID: [String: CGRect]

    /// Lays out `graph`, with `positionOverrides` (node-id → centre) taking precedence over
    /// computed positions — used to restore user drags.
    public init(graph: CallGraph, positionOverrides: [String: CGPoint] = [:]) {
        let sizes = Dictionary(
            graph.nodes.map { ($0.id, Self.estimatedSize(for: $0)) },
            uniquingKeysWith: { first, _ in first }
        )

        let inputs = graph.nodes.map {
            SugiyamaLayoutEngine.NodeInput(id: $0.id, size: sizes[$0.id] ?? .zero, group: nil)
        }
        let edgeInputs = graph.edges.map {
            SugiyamaLayoutEngine.EdgeInput(sourceID: $0.from, targetID: $0.to, kind: .inheritance)
        }
        var positions = SugiyamaLayoutEngine().layout(nodes: inputs, edges: edgeInputs).positions
        for (id, point) in positionOverrides {
            positions[id] = point
        }

        // Normalize so the content's top-left corner sits at the origin.
        var minX: CGFloat = .greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        for node in graph.nodes {
            let size = sizes[node.id] ?? .zero
            let center = positions[node.id] ?? .zero
            minX = min(minX, center.x - size.width / 2)
            minY = min(minY, center.y - size.height / 2)
        }
        if minX == .greatestFiniteMagnitude { minX = 0 }
        if minY == .greatestFiniteMagnitude { minY = 0 }

        var frames: [String: CGRect] = [:]
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        var nodeFrames: [NodeFrame] = []
        for node in graph.nodes {
            let size = sizes[node.id] ?? .zero
            let center = positions[node.id] ?? .zero
            let rect = CGRect(
                x: center.x - size.width / 2 - minX,
                y: center.y - size.height / 2 - minY,
                width: size.width,
                height: size.height
            )
            frames[node.id] = rect
            nodeFrames.append(NodeFrame(id: node.id, node: node, rect: rect))
            maxX = max(maxX, rect.maxX)
            maxY = max(maxY, rect.maxY)
        }

        nodes = nodeFrames
        framesByID = frames
        contentSize = CGSize(width: max(maxX, 1), height: max(maxY, 1))
        edges = graph.edges.enumerated().map { index, edge in
            EdgeLayout(id: index, from: edge.from, to: edge.to, weight: edge.weight)
        }
    }

    /// The laid-out frame for a method id, when it exists.
    public func frame(for id: String) -> CGRect? {
        framesByID[id]
    }

    /// Estimated render size for a method box: wide enough for its `Type.method` label.
    public static func estimatedSize(for node: CallGraph.Node) -> CGSize {
        let width = max(120, CGFloat(node.label.count) * 7 + 32)
        return CGSize(width: min(width, 320), height: 52)
    }
}
