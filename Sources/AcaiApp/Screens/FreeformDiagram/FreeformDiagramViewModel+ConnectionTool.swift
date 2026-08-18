import AcaiCore
import AcaiDiagram

// MARK: - Connection Tools (relationships / messages / transitions)
//
// `lastUsedConnectionTool` itself is a `@Published` stored property on `FreeformDiagramViewModel`
// (extensions can't add stored properties); everything else it drives lives here, split out to
// keep the main view model file under its type-body-length budget.

extension FreeformDiagramViewModel {
    /// Tracked so the compact bottom bar's quick-add slot can repeat whichever one the user
    /// reached for most recently.
    enum ConnectionTool: Equatable {
        case relationship(Relationship.Kind)
        case message(SequenceDiagram.Message.Kind)
        case transition
    }

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

    /// No-op if the selection doesn't fit.
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
