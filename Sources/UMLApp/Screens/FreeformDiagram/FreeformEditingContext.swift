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
