import CoreGraphics
import SwiftUI
import AcaiDiagram
import AcaiDiff

// Grouped parameter objects for the image renderers: the output-tuning knobs (scale/padding/palette)
// and the optional delta-tint closures collapse into one argument apiece so entry points stay narrow.
// `.default`/`.plain` vend a configured instance — a value, not an empty default.

/// Output tuning shared by every image renderer: the pixel `scale`, the content `padding` inset, and
/// the light/dark `palette`. `.default` is the standard 2× light configuration.
public struct RenderingContext: Sendable {
    public var scale: CGFloat
    public var padding: CGFloat
    public var palette: DiagramPalette

    public init(
        scale: CGFloat = 2,
        padding: CGFloat = DiagramImageRenderer.defaultPadding,
        palette: DiagramPalette = .light
    ) {
        self.scale = scale
        self.padding = padding
        self.palette = palette
    }

    public static let `default` = RenderingContext()
}

/// A fully laid-out class diagram ready to rasterize: the nodes/edges plus their resolved positions,
/// sizes, and grouping boxes (in any coordinate space — the renderer normalizes to the origin).
public struct LaidOutDiagram: Sendable {
    public var nodes: [GeneratedDiagramNode]
    public var edges: [GeneratedDiagramEdge]
    public var positions: [String: CGPoint]
    public var sizes: [String: CGSize]
    public var groupingBoxes: [DiagramLayoutModel.GroupingBox]

    public init(
        nodes: [GeneratedDiagramNode],
        edges: [GeneratedDiagramEdge],
        positions: [String: CGPoint],
        sizes: [String: CGSize],
        groupingBoxes: [DiagramLayoutModel.GroupingBox]
    ) {
        self.nodes = nodes
        self.edges = edges
        self.positions = positions
        self.sizes = sizes
        self.groupingBoxes = groupingBoxes
    }
}

/// Optional per-element delta tints for a class diagram (added green / removed red / changed amber);
/// a `nil` closure — or `.plain` — leaves every element its themed colour.
public struct ClassColorOverrides: Sendable {
    public var edge: (@Sendable (GeneratedDiagramEdge) -> Color?)?
    public var node: (@Sendable (GeneratedDiagramNode) -> Color?)?
    /// Non-color complement to `node`'s tint, so an exported image matches the on-screen canvas.
    public var badge: (@Sendable (GeneratedDiagramNode) -> DeltaStatus?)?

    public init(
        edge: (@Sendable (GeneratedDiagramEdge) -> Color?)? = nil,
        node: (@Sendable (GeneratedDiagramNode) -> Color?)? = nil,
        badge: (@Sendable (GeneratedDiagramNode) -> DeltaStatus?)? = nil
    ) {
        self.edge = edge
        self.node = node
        self.badge = badge
    }

    /// No delta tint — every element keeps its themed colour.
    public static let plain = ClassColorOverrides()
}

/// Optional delta tints for the id-keyed graph diagrams (package, call graph): a node closure keyed by
/// node id and an edge closure keyed by `(from, to)`. `.plain` leaves everything its themed colour.
public struct GraphColorOverrides: Sendable {
    public var node: (@Sendable (String) -> Color?)?
    public var edge: (@Sendable (String, String) -> Color?)?

    public init(
        node: (@Sendable (String) -> Color?)? = nil,
        edge: (@Sendable (String, String) -> Color?)? = nil
    ) {
        self.node = node
        self.edge = edge
    }

    /// No delta tint — every element keeps its themed colour.
    public static let plain = GraphColorOverrides()
}
