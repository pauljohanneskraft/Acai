import Foundation
import UMLDiagram

// MARK: - State Elements (states + labeled transitions)
//
// Custom diagrams render their state nodes through the same `StateNodeView` the generated
// state view uses, so a state diagram saved as a custom diagram looks identical to its
// generated original — while every state and transition stays an ordinary, fully editable
// node/edge. Transitions are plain edges carrying a `transition` payload (event/guard/action).

extension CustomDiagramViewModel {

    /// Whether a node is a state-machine state.
    func isStateNode(_ nodeID: String) -> Bool {
        guard let node = nodes.first(where: { $0.id == nodeID }) else { return false }
        if case .state = node.content { return true }
        return false
    }

    /// The selected state-node ids in click order (drives transition direction: first → second).
    var orderedStateSelection: [String] {
        selectionOrder.filter { isStateNode($0) }
    }

    /// Add a transition edge between two states and select it so the inspector opens
    /// straight onto the event/guard/action fields. `sourceID == targetID` makes a self-loop.
    func addTransition(from sourceID: String, to targetID: String) {
        recordUndo()
        var edge = CustomDiagram.Edge(sourceNodeID: sourceID, targetNodeID: targetID, kind: .association)
        edge.transition = .init()
        edges.append(edge)
        selectedEdgeID = edge.id
        save()
    }

    /// Update a transition edge's event, guard and/or action as one undoable step.
    func updateTransitionEdge(
        _ edgeID: String,
        event: String? = nil,
        guardCondition: String? = nil,
        action: String? = nil
    ) {
        guard let idx = edges.firstIndex(where: { $0.id == edgeID }),
              var transition = edges[idx].transition else { return }
        recordUndo(coalescingKey: "transitionEdge-\(edgeID)")
        if let event { transition.event = event.isEmpty ? nil : event }
        if let guardCondition { transition.guardCondition = guardCondition.isEmpty ? nil : guardCondition }
        if let action { transition.action = action.isEmpty ? nil : action }
        edges[idx].transition = transition
        save()
    }

    /// Update a state node's UML flavour (normal, initial, final, choice, …).
    func updateStateKind(_ nodeID: String, kind: StateDiagram.State.Kind) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }),
              case .state = nodes[idx].content else { return }
        recordUndo()
        nodes[idx].content = .state(kind)
        save()
    }
}
