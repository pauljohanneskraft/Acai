import Foundation
import AcaiCore
import AcaiDiagram

/// Converts a state diagram into an editable freeform diagram: each state becomes a state node
/// and every transition a labeled transition edge. The freeform editor renders these through the
/// same `StateNodeView` the generated view uses, so the converted diagram looks identical to its
/// original while staying fully editable.
struct StateFreeformConversion: FreeformConversion {
    let context: FreeformConversionContext
    private let state: StateDiagram

    init(context: FreeformConversionContext, configuration: StateDiagramConfiguration) {
        self.context = context
        // Analysis failures convert to an empty (but still editable) diagram.
        self.state = (try? StateDiagramBuilder(configuration: configuration)
            .build(from: context.artifact.resolvingExtensions())) ?? StateDiagram()
    }

    func items() -> [StateDiagram.State] {
        state.states
    }

    func sourceID(for item: StateDiagram.State) -> String {
        item.id
    }

    func defaultPosition(index: Int) -> CGPoint {
        CGPoint(x: CGFloat(index) * 160 + 120, y: 100)
    }

    func makeNode(for item: StateDiagram.State, id: String, position: CGPoint) -> FreeformDiagram.Node {
        FreeformDiagram.Node(
            id: id,
            name: item.name,
            content: .state(item.kind),
            positionX: Double(position.x),
            positionY: Double(position.y)
        )
    }

    func makeEdges(idsBySourceID: [String: String]) -> [FreeformDiagram.Edge] {
        state.transitions.compactMap { transition in
            guard let source = idsBySourceID[transition.from],
                  let target = idsBySourceID[transition.to] else { return nil }
            var edge = FreeformDiagram.Edge(sourceNodeID: source, targetNodeID: target, kind: .association)
            edge.transition = .init(
                event: transition.event,
                guardCondition: transition.guardCondition,
                action: transition.action
            )
            return edge
        }
    }
}
