import CoreGraphics
import Foundation
import AcaiCore
import AcaiDiagram

/// Computes node frames and edge routes for a `CallGraph` via the shared `SugiyamaLayoutEngine`.
/// Calls are fed as `.inheritance` edges so `LayerAssignment` stacks callers above callees.
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

    public func frame(for id: String) -> CGRect? {
        framesByID[id]
    }

    public static func estimatedSize(for node: CallGraph.Node) -> CGSize {
        let width = max(120, CGFloat(node.label.count) * 7 + 32)
        return CGSize(width: min(width, 320), height: 52)
    }
}
