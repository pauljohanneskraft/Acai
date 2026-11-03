import CoreGraphics
import AcaiDiff
import AcaiRender

extension StateDiagramViewModel {
    var rotorPlan: DiagramRotorPlan {
        let layout = layout
        return DiagramRotorPlan(
            elements: layout.nodes.map { node in
                DiagramRotorPlan.Element(
                    id: node.id, label: node.state.name, delta: stateDeltaStatus(node.id), frame: node.rect
                )
            },
            connections: layout.edges.compactMap { edge in
                guard let source = layout.frame(for: edge.from), let target = layout.frame(for: edge.to) else {
                    return nil
                }
                return DiagramRotorPlan.Element(
                    connection: edge.accessibilityID, label: transitionDescription(edge).summary,
                    delta: transitionDelta(edge), from: source, to: target
                )
            }
        )
    }

    func transitionDescription(_ edge: StateLayoutModel.EdgeLayout) -> DiagramElementDescription {
        DiagramElementDescription(
            edgeFrom: stateName(edge.from) ?? edge.from,
            to: stateName(edge.to) ?? edge.to,
            details: [],
            delta: transitionDelta(edge))
    }

    private func transitionDelta(_ edge: StateLayoutModel.EdgeLayout) -> DeltaStatus? {
        let transitions = diagram?.transitions ?? []
        return transitions.indices.contains(edge.id) ? transitionDeltaStatus(transitions[edge.id]) : nil
    }
}

extension StateLayoutModel.EdgeLayout {
    var accessibilityID: String {
        "diagram.stateTransition.\(id)"
    }
}
