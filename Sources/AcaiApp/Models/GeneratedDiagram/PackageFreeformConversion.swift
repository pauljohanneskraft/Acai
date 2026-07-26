import Foundation
import AcaiCore
import AcaiDiagram

/// Converts a package diagram into an editable freeform diagram: each module becomes a UML
/// `.package` node (the same shape the generated view shows) and every cross-module dependency a
/// dependency edge. Coupling metrics aren't carried over by default — a hand-edited package
/// diagram has no analysis behind it — but when `includeMetricsNote` is set (B22), one read-only
/// `.note` node summarizing every module's Ca/Ce/I/A/D is appended instead of silently dropping
/// the figures.
struct PackageFreeformConversion: FreeformConversion {
    let context: FreeformConversionContext
    let includeMetricsNote: Bool
    private let package: PackageDiagram

    init(context: FreeformConversionContext, includeMetricsNote: Bool) {
        self.context = context
        self.includeMetricsNote = includeMetricsNote
        self.package = PackageDiagramBuilder().build(
            from: context.artifact.enriched(using: context.artifact.standardLanguageResolver))
    }

    func items() -> [PackageDiagram.Node] {
        package.nodes
    }

    func sourceID(for item: PackageDiagram.Node) -> String {
        item.id
    }

    func defaultPosition(index: Int) -> CGPoint {
        CGPoint(x: CGFloat(index) * 200 + 120, y: 120)
    }

    func makeNode(for item: PackageDiagram.Node, id: String, position: CGPoint) -> FreeformDiagram.Node {
        FreeformDiagram.Node(
            id: id,
            name: item.name,
            content: .package,
            positionX: Double(position.x),
            positionY: Double(position.y)
        )
    }

    func makeEdges(idsBySourceID: [String: String]) -> [FreeformDiagram.Edge] {
        package.edges.compactMap { edge in
            guard let source = idsBySourceID[edge.from],
                  let target = idsBySourceID[edge.to] else { return nil }
            return FreeformDiagram.Edge(sourceNodeID: source, targetNodeID: target, kind: .dependency)
        }
    }

    func metricsFooterNodes(existingNodes: [FreeformDiagram.Node]) -> [FreeformDiagram.Node] {
        guard includeMetricsNote, !package.nodes.isEmpty else { return [] }
        let maxY = existingNodes.map(\.positionY).max() ?? 120
        return [FreeformDiagram.Node(
            name: "Coupling Metrics (read-only)",
            content: .note(text: package.metricsNoteText),
            positionX: 120,
            positionY: maxY + 220
        )]
    }
}
