import Foundation
import UMLDiagram

/// State-machine editing for the freeform diagram: states and labeled transitions.
///
/// Freeform diagrams render their state nodes through the same `StateNodeView` the generated
/// state view uses, so a state diagram saved as a freeform diagram looks identical to its
/// generated original — while every state and transition stays an ordinary, fully editable
/// node/edge. Transitions are plain edges carrying a `transition` payload (event/guard/action).
@MainActor
final class StateMachineEditor {
    private unowned let context: any FreeformEditingContext

    init(context: any FreeformEditingContext) {
        self.context = context
    }

    /// Whether a node is a state-machine state.
    func isStateNode(_ nodeID: String) -> Bool {
        guard let node = context.nodes.first(where: { $0.id == nodeID }) else { return false }
        if case .state = node.content { return true }
        return false
    }

    /// The selected state-node ids in click order (drives transition direction: first → second).
    var orderedStateSelection: [String] {
        context.selectionOrder.filter { isStateNode($0) }
    }

    /// Add a transition edge between two states and select it so the inspector opens
    /// straight onto the event/guard/action fields. `sourceID == targetID` makes a self-loop.
    func addTransition(from sourceID: String, to targetID: String) {
        context.recordUndo(coalescingKey: nil)
        var edge = FreeformDiagram.Edge(sourceNodeID: sourceID, targetNodeID: targetID, kind: .association)
        edge.transition = .init()
        context.edges.append(edge)
        context.selectedEdgeID = edge.id
        context.save()
    }

    /// Update a transition edge's event, guard and/or action as one undoable step.
    func updateTransitionEdge(
        _ edgeID: String,
        event: String? = nil,
        guardCondition: String? = nil,
        action: String? = nil
    ) {
        guard let idx = context.edges.firstIndex(where: { $0.id == edgeID }),
              var transition = context.edges[idx].transition else { return }
        context.recordUndo(coalescingKey: "transitionEdge-\(edgeID)")
        if let event { transition.event = event.isEmpty ? nil : event }
        if let guardCondition { transition.guardCondition = guardCondition.isEmpty ? nil : guardCondition }
        if let action { transition.action = action.isEmpty ? nil : action }
        context.edges[idx].transition = transition
        context.save()
    }

    /// Update a state node's UML flavour (normal, initial, final, choice, …).
    func updateStateKind(_ nodeID: String, kind: StateDiagram.State.Kind) {
        guard let idx = context.nodes.firstIndex(where: { $0.id == nodeID }),
              case .state = context.nodes[idx].content else { return }
        context.recordUndo(coalescingKey: nil)
        context.nodes[idx].content = .state(kind)
        context.save()
    }
}
