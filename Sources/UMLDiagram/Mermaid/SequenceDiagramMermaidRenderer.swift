/// Renders a `SequenceDiagram` to a Mermaid `sequenceDiagram`.
public struct SequenceDiagramMermaidRenderer: Sendable {
    public init() {}

    public func render(_ diagram: SequenceDiagram) -> String {
        var lines = ["sequenceDiagram"]

        var idMap: [String: String] = [:]
        for participant in diagram.participants {
            let safe = participant.id.mermaidSafeID
            idMap[participant.id] = safe
            lines.append("    participant \(safe) as \(participant.name.mermaidLabelEscaped)")
        }

        for message in diagram.messages.sorted(by: { $0.order < $1.order }) {
            guard let from = idMap[message.from], let to = idMap[message.to] else { continue }
            lines.append("    \(from)\(arrowToken(for: message.kind))\(to): \(label(for: message))")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func arrowToken(for kind: SequenceDiagram.Message.Kind) -> String {
        switch kind {
        case .synchronous, .create, .destroy:
            return "->>"
        case .asynchronous:
            return "-)"
        case .return:
            return "-->>"
        }
    }

    private func label(for message: SequenceDiagram.Message) -> String {
        let text = (message.label ?? "").mermaidTextEscaped
        switch message.kind {
        case .create:
            return text.isEmpty ? "«create»" : "«create» \(text)"
        case .destroy:
            return text.isEmpty ? "«destroy»" : "«destroy» \(text)"
        default:
            return text
        }
    }
}
