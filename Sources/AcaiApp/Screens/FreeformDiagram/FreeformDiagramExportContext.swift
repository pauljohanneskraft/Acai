import Foundation

/// A minimal, otherwise-unused `FreeformEditingContext` so export can reuse `SequenceEditor`'s
/// lifeline/message/fragment layout logic instead of duplicating it — the mutating requirements
/// are never called on this path.
final class FreeformDiagramExportContext: FreeformEditingContext {
    var nodes: [FreeformDiagram.Node]
    var edges: [FreeformDiagram.Edge]
    var selectedNodeIDs: Set<String> = []
    var selectedEdgeID: String?
    var selectionOrder: [String] { [] }

    init(nodes: [FreeformDiagram.Node], edges: [FreeformDiagram.Edge]) {
        self.nodes = nodes
        self.edges = edges
    }

    func recordUndo(coalescingKey: AnyHashable?) {}
    func save() {}
    func removeNodes(_ ids: Set<String>) {}
}
