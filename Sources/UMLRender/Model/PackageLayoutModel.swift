import CoreGraphics
import Foundation
import UMLCore
import UMLDiagram

/// Computes node frames and edge routes for a `PackageDependencyDiagram`.
///
/// Modules and their dependencies form a plain directed graph, so layout delegates to the
/// shared `SugiyamaLayoutEngine` — the same approach `StateLayoutModel` uses. Dependency
/// edges are fed as `.inheritance` so `LayerAssignment` lifts the most depended-upon
/// (foundational) modules toward the top and lays dependents out beneath them.
public struct PackageLayoutModel: Sendable {

    public struct NodeFrame: Identifiable, Sendable {
        public let id: String
        public let node: PackageDependencyDiagram.Node
        public let rect: CGRect
    }

    public struct EdgeLayout: Identifiable, Sendable {
        public let id: Int
        public let from: String
        public let to: String
        /// Cross-module reference count — drives line thickness (not a text label).
        public let weight: Int
    }

    public let nodes: [NodeFrame]
    public let edges: [EdgeLayout]
    public let contentSize: CGSize

    private let framesByID: [String: CGRect]

    /// Lays out `diagram`, with `positionOverrides` (node-id → centre) taking precedence over
    /// computed positions — used to restore user drags.
    public init(diagram: PackageDependencyDiagram, positionOverrides: [String: CGPoint] = [:]) {
        // Feed each dependency as an inheritance edge to its target so depended-upon modules
        // (e.g. a core module) rise to the top layer and dependents flow downward.
        let layout = DirectedGraphLayout(
            nodeSizes: diagram.nodes.map { ($0.id, Self.estimatedSize(for: $0)) },
            edges: diagram.edges.map { ($0.from, $0.to) },
            positionOverrides: positionOverrides
        )
        framesByID = layout.framesByID
        contentSize = layout.contentSize
        nodes = diagram.nodes.map { NodeFrame(id: $0.id, node: $0, rect: layout.framesByID[$0.id] ?? .zero) }
        edges = diagram.edges.enumerated().map { index, edge in
            EdgeLayout(id: index, from: edge.from, to: edge.to, weight: edge.weight)
        }
    }

    /// The laid-out frame for a module id, when the module exists.
    public func frame(for id: String) -> CGRect? {
        framesByID[id]
    }

    /// Estimated render size for a module's package box: wide enough for its name plus the
    /// folder chrome, with a fixed height (the body area is empty in a dependency view).
    public static func estimatedSize(for node: PackageDependencyDiagram.Node) -> CGSize {
        let width = max(140, CGFloat(node.name.count) * 8 + 40)
        return CGSize(width: min(width, 320), height: 72)
    }
}
