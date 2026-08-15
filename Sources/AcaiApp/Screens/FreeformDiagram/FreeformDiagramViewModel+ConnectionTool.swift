import AcaiCore
import AcaiDiagram

// MARK: - Connection Tools (relationships / messages / transitions)
//
// `lastUsedConnectionTool` itself is a `@Published` stored property on `FreeformDiagramViewModel`
// (extensions can't add stored properties); everything else it drives lives here, split out to
// keep the main view model file under its type-body-length budget.

extension FreeformDiagramViewModel {
    /// A kind of connector the Node/Relationship/Message/Transition catalogs can add between
    /// selected elements. Tracked so the compact bottom bar's quick-add slot can repeat whichever
    /// one the user reached for most recently.
    enum ConnectionTool: Equatable {
        case relationship(Relationship.Kind)
        case message(SequenceDiagram.Message.Kind)
        case transition
    }

    /// SF Symbol name for `ConnectionTool`'s bottom-bar quick-add button.
    var lastUsedConnectionToolSystemImage: String {
        switch lastUsedConnectionTool {
        case .relationship, .transition:
            "arrow.right"
        case .message(let kind):
            switch kind {
            case .asynchronous:
                "arrow.right.to.line"
            case .return:
                "arrowshape.turn.up.left"
            case .synchronous, .create, .destroy:
                "arrow.right"
            }
        }
    }

    /// Whether `applyLastUsedConnectionTool()` would do anything given the current selection.
    var canApplyLastUsedConnectionTool: Bool {
        switch lastUsedConnectionTool {
        case .relationship:
            selectedNodeIDs.count == 2
        case .message:
            (1...2).contains(sequence.orderedLifelineSelection.count)
        case .transition:
            (1...2).contains(state.orderedStateSelection.count)
        }
    }

    /// Applies `lastUsedConnectionTool` to the current selection: a relationship between two
    /// selected nodes, a message between one (self) or two selected lifelines, or a transition
    /// between one (self) or two selected states. No-op if the selection doesn't fit.
    func applyLastUsedConnectionTool() {
        switch lastUsedConnectionTool {
        case .relationship(let kind):
            guard selectionOrder.count == 2 else { return }
            addEdge(from: selectionOrder[0], to: selectionOrder[1], kind: kind)
        case .message(let kind):
            let lifelines = sequence.orderedLifelineSelection
            guard (1...2).contains(lifelines.count) else { return }
            if lifelines.count == 1 {
                sequence.addMessage(from: lifelines[0], to: lifelines[0], kind: kind)
            } else {
                sequence.addMessage(from: lifelines[0], to: lifelines[1], kind: kind)
            }
        case .transition:
            let states = state.orderedStateSelection
            guard (1...2).contains(states.count) else { return }
            if states.count == 1 {
                state.addTransition(from: states[0], to: states[0])
            } else {
                state.addTransition(from: states[0], to: states[1])
            }
        }
    }
}
