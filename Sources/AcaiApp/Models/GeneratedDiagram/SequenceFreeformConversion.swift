import Foundation
import AcaiCore
import AcaiDiagram

/// Converts a sequence diagram into an editable freeform diagram: each participant becomes a
/// lifeline node and every message (calls *and* returns) becomes a time-ordered message edge. The
/// freeform editor renders these through the same sequence layout the generated view uses, so the
/// converted diagram looks identical to its original while staying fully editable (move, relabel,
/// reorder, add/remove).
struct SequenceFreeformConversion: FreeformConversion {
    let context: FreeformConversionContext
    private let sequence: SequenceDiagram

    init(context: FreeformConversionContext, configuration: SequenceDiagramConfiguration) {
        self.context = context
        self.sequence = SequenceDiagramBuilder(
            entryPoint: (configuration.entryTypeName, configuration.entryMethodName),
            maxDepth: configuration.maxDepth,
            typeMapping: configuration.typeMapping
        ).build(from: context.artifact)
    }

    func items() -> [SequenceDiagram.Participant] {
        sequence.participants
    }

    func sourceID(for item: SequenceDiagram.Participant) -> String {
        item.id
    }

    func defaultPosition(index: Int) -> CGPoint {
        CGPoint(x: CGFloat(index) * 180 + 120, y: 100)
    }

    /// Lifelines always sit on one fixed horizontal line: unlike the shared three-tier default,
    /// only `x` is ever data-driven (from a live position — participants have no stored-position
    /// tier at all, since a sequence diagram itself never persists per-participant positions).
    func resolvedPosition(for item: SequenceDiagram.Participant, sourceID: String, index: Int) -> CGPoint {
        CGPoint(x: positions[sourceID]?.x ?? defaultPosition(index: index).x, y: defaultPosition(index: index).y)
    }

    func makeNode(for item: SequenceDiagram.Participant, id: String, position: CGPoint) -> FreeformDiagram.Node {
        FreeformDiagram.Node(
            id: id,
            name: item.name,
            content: .lifeline(item.kind),
            positionX: Double(position.x),
            positionY: Double(position.y)
        )
    }

    func makeEdges(idsBySourceID: [String: String]) -> [FreeformDiagram.Edge] {
        sequence.messages
            .sorted { $0.order < $1.order }
            .compactMap { message in
                guard let source = idsBySourceID[message.from],
                      let target = idsBySourceID[message.to] else { return nil }
                return FreeformDiagram.Edge(
                    sourceNodeID: source,
                    targetNodeID: target,
                    kind: .dependency,
                    label: message.label,
                    messageOrder: message.order,
                    messageKind: message.kind
                )
            }
    }
}
