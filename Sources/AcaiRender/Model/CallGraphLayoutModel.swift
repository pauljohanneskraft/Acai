import CoreGraphics
import Foundation
import AcaiCore
import AcaiDiagram

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
        let layout = DirectedGraphLayout(
            nodeSizes: graph.nodes.map { ($0.id, Self.estimatedSize(for: $0)) },
            edges: graph.edges.map { ($0.from, $0.to) },
            positionOverrides: positionOverrides
        )
        framesByID = layout.framesByID
        contentSize = layout.contentSize
        nodes = graph.nodes.map { NodeFrame(id: $0.id, node: $0, rect: layout.framesByID[$0.id] ?? .zero) }
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
