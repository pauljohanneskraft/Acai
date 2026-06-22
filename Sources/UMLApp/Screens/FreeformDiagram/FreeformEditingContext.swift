import Foundation

/// The slice of `FreeformDiagramViewModel` that the freeform editing collaborators
/// (``SequenceEditor``, ``StateMachineEditor``, ``TypeMemberEditor``, ``SelectionClipboard``)
/// operate on. Keeping them behind this seam means each owns one editing domain without depending
/// on the whole view model, and each can be unit-tested against a lightweight stub.
@MainActor
protocol FreeformEditingContext: AnyObject {
    var nodes: [FreeformDiagram.Node] { get set }
    var edges: [FreeformDiagram.Edge] { get set }
    var selectedNodeIDs: Set<String> { get set }
    var selectedEdgeID: String? { get set }
    /// Selected node ids in click order — drives "first selected → second selected" direction.
    var selectionOrder: [String] { get }

    /// Capture the current state as an undo checkpoint before a mutation (see `DiagramHistoryHosting`).
    func recordUndo(coalescingKey: AnyHashable?)
    /// Persist the current nodes and edges.
    func save()
    /// Remove the given nodes and any edges touching them, dropping them from the selection.
    func removeNodes(_ ids: Set<String>)
}

extension FreeformEditingContext {
    /// The node with this id, or `nil` if unknown. The single lookup behind the editors'
    /// content-kind predicates.
    func node(_ id: String) -> FreeformDiagram.Node? {
        nodes.first { $0.id == id }
    }

    /// Mutate the `.type` payload of a node by id as one undoable step. No-op if the node is
    /// missing or isn't a type node — the guard runs before `recordUndo`, so a wrong-kind node
    /// records no empty undo step.
    func updateTypeContent(
        _ id: String,
        coalescingKey: AnyHashable? = nil,
        _ mutate: (inout FreeformDiagram.Node.TypeContent) -> Void
    ) {
        guard let idx = nodes.firstIndex(where: { $0.id == id }),
              case .type(var content) = nodes[idx].content else { return }
        recordUndo(coalescingKey: coalescingKey)
        mutate(&content)
        nodes[idx].content = .type(content)
        save()
    }
}
