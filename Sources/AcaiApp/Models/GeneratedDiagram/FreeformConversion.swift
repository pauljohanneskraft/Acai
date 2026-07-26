import Foundation
import AcaiCore

/// The values every "Save as Freeform" conversion needs regardless of diagram type — bundled so a
/// `FreeformConversion` conformer's initializer stays under `swiftlint`'s `function_parameter_count`
/// limit once its own per-type extras (a configuration, a scope, `includeMetricsNote`, …) are added.
struct FreeformConversionContext {
    let diagram: GeneratedDiagram
    let artifact: CodeArtifact
    let positions: [String: CGPoint]
    let scale: CGFloat
    let offset: CGPoint
}

/// The shared shape of every "Save as Freeform" conversion (B23): dispatch to one of these five
/// conformers (`ClassFreeformConversion`, `SequenceFreeformConversion`, `StateFreeformConversion`,
/// `PackageFreeformConversion`, `CallGraphFreeformConversion`), each a value built for one
/// conversion and asked to `makeFreeformDiagram()`.
///
/// What's genuinely shared (pulled into this protocol's default implementation): the outer skeleton
/// (build the domain diagram → one freeform node per domain item, id-mapped → wrap the result in a
/// `FreeformDiagram`), the id-map bookkeeping, and the position-fallback tiering (live `positions`
/// entry → the diagram's stored `nodePositions` → a per-type staggered default).
///
/// What's deliberately **not** forced into a shared shape, because the five conversions'
/// requirements genuinely differ (see `GeneratedDiagram+Freeform.swift`'s doc comment and B23's
/// backlog entry for why): per-item node/edge content construction (`makeNode`/`makeEdges` — a
/// class's full member list has nothing in common with a lifeline or a package box), grouping-box
/// materialization (Class-only), and B22's metrics-footer note (Package/Call Graph-only). Those
/// three are default-no-op hooks a conformer overrides only when it needs them, rather than every
/// conformer being forced to implement a "grouping" or "metrics" concept that doesn't apply to it.
protocol FreeformConversion {
    /// The domain-specific item each source element converts to one freeform node from (a
    /// `TypeDeclaration`, a `SequenceDiagram.Participant`, a `PackageDiagram.Node`, …).
    associatedtype Item

    var context: FreeformConversionContext { get }

    /// The domain items to convert, one node each (after first-wins dedup by `sourceID`).
    func items() -> [Item]
    /// The stable id (from the source domain, not the freeform node) used to key into `positions`/
    /// `context.diagram.nodePositions` and the id-map handed to `makeEdges`.
    func sourceID(for item: Item) -> String
    /// The staggered position used when an item has neither a live nor a stored position. Every
    /// conformer states its own — the stride differs slightly by type, and one conformer
    /// (`SequenceFreeformConversion`) also needs a fixed (non-staggered) `y`.
    func defaultPosition(index: Int) -> CGPoint
    /// Resolves one item's canvas position. The default implementation is the shared three-tier
    /// fallback documented above; `SequenceFreeformConversion` overrides it (lifelines sit on one
    /// fixed horizontal line, so only `x` is ever data-driven, and there's no stored-position tier).
    func resolvedPosition(for item: Item, sourceID: String, index: Int) -> CGPoint

    /// Builds the one freeform node for `item`, at its already-resolved `position`.
    func makeNode(for item: Item, id: String, position: CGPoint) -> FreeformDiagram.Node
    /// Builds every edge, once every item's freeform node id is known (`idsBySourceID`).
    func makeEdges(idsBySourceID: [String: String]) -> [FreeformDiagram.Edge]

    /// Grouping/container nodes drawn behind `memberNodes` (Class diagram's directory/product
    /// boxes only). Defaults to none.
    func groupingNodes(memberNodes: [FreeformDiagram.Node], idsBySourceID: [String: String]) -> [FreeformDiagram.Node]
    /// B22's opt-in read-only metrics summary (Package/Call Graph only). Defaults to none.
    func metricsFooterNodes(existingNodes: [FreeformDiagram.Node]) -> [FreeformDiagram.Node]
}

extension FreeformConversion {
    var diagram: GeneratedDiagram { context.diagram }
    var artifact: CodeArtifact { context.artifact }
    var positions: [String: CGPoint] { context.positions }
    var scale: CGFloat { context.scale }
    var offset: CGPoint { context.offset }

    func resolvedPosition(for item: Item, sourceID: String, index: Int) -> CGPoint {
        if let live = positions[sourceID] { return live }
        if let stored = diagram.nodePositions[sourceID] { return stored.cgPoint }
        return defaultPosition(index: index)
    }

    func groupingNodes(memberNodes: [FreeformDiagram.Node], idsBySourceID: [String: String]) -> [FreeformDiagram.Node] {
        []
    }

    func metricsFooterNodes(existingNodes: [FreeformDiagram.Node]) -> [FreeformDiagram.Node] {
        []
    }

    /// Runs the shared skeleton: one node per item (first-wins on a repeated `sourceID`, mirroring
    /// how a language that doesn't qualify by module can report two distinct types under one id),
    /// then edges, then the optional grouping/metrics-footer hooks, wrapped in a `FreeformDiagram`
    /// named and positioned to match the diagram being converted.
    func makeFreeformDiagram() -> FreeformDiagram {
        var idsBySourceID: [String: String] = [:]
        var nodes: [FreeformDiagram.Node] = []
        for (index, item) in items().enumerated() {
            let itemID = sourceID(for: item)
            guard idsBySourceID[itemID] == nil else { continue }
            let nodeID = UUID().uuidString
            idsBySourceID[itemID] = nodeID
            let position = resolvedPosition(for: item, sourceID: itemID, index: index)
            nodes.append(makeNode(for: item, id: nodeID, position: position))
        }

        let edges = makeEdges(idsBySourceID: idsBySourceID)
        let grouping = groupingNodes(memberNodes: nodes, idsBySourceID: idsBySourceID)
        let footer = metricsFooterNodes(existingNodes: nodes)

        return FreeformDiagram(
            name: diagram.name + " (Freeform)",
            nodes: grouping + nodes + footer,
            edges: edges,
            canvasScale: scale,
            canvasOffsetX: offset.x,
            canvasOffsetY: offset.y
        )
    }
}
