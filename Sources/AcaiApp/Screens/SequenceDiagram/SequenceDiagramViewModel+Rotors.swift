import CoreGraphics
import AcaiDiagram
import AcaiRender

extension SequenceDiagramViewModel {
    var rotorPlan: DiagramRotorPlan {
        rotorPlanCache.plan { freshRotorPlan }
    }

    private var freshRotorPlan: DiagramRotorPlan {
        let layout = layout
        let messages = orderedMessages
        let names = Dictionary(layout.participants.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return DiagramRotorPlan(
            elements: layout.participants.map { participant in
                DiagramRotorPlan.Element(
                    id: participant.id, label: participant.name,
                    delta: participantDeltaStatus(participant.id), frame: participant.headerRect
                )
            },
            connections: layout.messages.map { message in
                DiagramRotorPlan.Element(
                    connection: message.accessibilityID,
                    label: messageDescription(message, messages: messages, names: names).summary,
                    delta: messages.indices.contains(message.id) ? messageDeltaStatus(messages[message.id]) : nil,
                    midpoint: CGPoint(x: (message.fromX + message.toX) / 2, y: message.y)
                )
            }
        )
    }

    private func messageDescription(
        _ layout: SequenceLayoutModel.MessageLayout, messages: [SequenceDiagram.Message], names: [String: String]
    ) -> DiagramElementDescription {
        guard messages.indices.contains(layout.id) else {
            return DiagramElementDescription(label: "", details: [])
        }
        let message = messages[layout.id]
        return DiagramElementDescription(
            edgeFrom: names[message.from] ?? message.from,
            to: names[message.to] ?? message.to,
            details: layout.label.map { [.app("DiagramElementDescription.EdgeLabel \($0)")] } ?? [],
            delta: messageDeltaStatus(message))
    }
}

extension SequenceLayoutModel.MessageLayout {
    var accessibilityID: String {
        "diagram.sequenceMessage.\(id)"
    }
}
