import CoreGraphics
import Foundation
import AcaiCore
import AcaiDiagram

/// Computes node frames and edge routes for a `PackageDiagram` via the shared
/// `SugiyamaLayoutEngine`. Dependency edges are fed as `.inheritance` so `LayerAssignment` lifts
/// the most depended-upon (foundational) modules toward the top.
public struct PackageLayoutModel: Sendable {

    public struct NodeFrame: Identifiable, Sendable {
        public let id: String
        public let node: PackageDiagram.Node
        public let rect: CGRect
    }

    public struct EdgeLayout: Identifiable, Sendable {
        public let id: Int
        public let from: String
        public let to: String
        /// Cross-module reference count — drives line thickness (not a text label).
        public let weight: Int
    }

    /// A labelled box around one project's modules, drawn behind them. Empty for a folder with a
    /// single project, where every module shares the one project and a box says nothing.
    public struct ProjectBox: Identifiable, Sendable {
        public let id: String
        public let label: String
        public let rect: CGRect
    }

    public let nodes: [NodeFrame]
    public let edges: [EdgeLayout]
    public let contentSize: CGSize
    public let projectBoxes: [ProjectBox]

    /// The node-free strip each box reserves at its top for its title tab, matching
    /// `GroupingBoxView`'s own tab so the tab never draws over the box's first module.
    private static let titleStrip: CGFloat = 30

    private let framesByID: [String: CGRect]

    public init(diagram: PackageDiagram, positionOverrides: [String: CGPoint] = [:]) {
        let projects = diagram.nodes.reduce(into: [String: String]()) { groups, node in
            if let project = node.project { groups[node.id] = project }
        }
        let layout = DirectedGraphLayout(
            nodeSizes: diagram.nodes.map { ($0.id, Self.estimatedSize(for: $0)) },
            edges: diagram.edges.map { ($0.from, $0.to) },
            positionOverrides: positionOverrides,
            groups: projects
        )
        framesByID = layout.framesByID
        contentSize = layout.contentSize
        nodes = diagram.nodes.map { NodeFrame(id: $0.id, node: $0, rect: layout.framesByID[$0.id] ?? .zero) }
        edges = diagram.edges.enumerated().map { index, edge in
            EdgeLayout(id: index, from: edge.from, to: edge.to, weight: edge.weight)
        }

        var bounds: [String: CGRect] = [:]
        for node in diagram.nodes {
            guard let project = node.project, let rect = layout.framesByID[node.id] else { continue }
            bounds[project] = bounds[project]?.union(rect) ?? rect
        }
        let strip = Self.titleStrip
        projectBoxes = bounds.sorted { $0.key < $1.key }.map {
            ProjectBox(id: $0.key, label: $0.key, rect: $0.value.insetBy(dx: -strip, dy: -strip))
        }
    }

    public func frame(for id: String) -> CGRect? {
        framesByID[id]
    }

    /// Estimated render size for a module's package box: wide enough for its name plus the
    /// folder chrome, with a fixed height (the body area is empty in a dependency view).
    public static func estimatedSize(for node: PackageDiagram.Node) -> CGSize {
        let width = max(140, CGFloat(node.moduleName.count) * 8 + 40)
        return CGSize(width: min(width, 320), height: 72)
    }
}
