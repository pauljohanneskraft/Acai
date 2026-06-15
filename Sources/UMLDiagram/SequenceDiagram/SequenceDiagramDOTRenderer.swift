/// Renders a `SequenceDiagram` to Graphviz DOT format.
///
/// DOT is not natively designed for sequence diagrams, so a rank-based layout is used:
/// - Participant headers share the topmost rank (left to right).
/// - For each message step an invisible intermediate node is created per participant.
/// - `{ rank=same }` constraints align all nodes at the same step horizontally.
/// - Invisible vertical edges along each lifeline establish the top-to-bottom ordering.
/// - Message arrows are drawn between the corresponding step nodes.
public struct SequenceDiagramDOTRenderer: DOTRenderer {
    public let renderOptions: DiagramRenderOptions

    public init(
        theme: DiagramTheme? = nil,
        fontName: String = "Helvetica",
        fontSize: Int = 12
    ) {
        self.renderOptions = DiagramRenderOptions(theme: theme, fontName: fontName, fontSize: fontSize)
    }

    /// Cosmetic node fill/border/font attributes when themed, else empty (structural outline).
    private var nodeColorAttrs: String {
        guard let theme else { return "" }
        return " style=filled fillcolor=\"\(theme.nodeFillColor)\""
            + " color=\"\(theme.nodeBorderColor)\" fontcolor=\"\(theme.fontColor)\""
    }

    // MARK: - Public API

    public func render(_ diagram: SequenceDiagram) -> String {
        let participants = diagram.participants
        let messages = diagram.messages.sorted { $0.order < $1.order }
        let steps = messages.count

        var out = "digraph {\n"
        if let title = diagram.title {
            out += "  label=\"\(title.dotEscaped)\";\n"
            out += "  labelloc=t;\n"
        }
        out += graphAttributes()

        renderParticipantHeaders(participants, into: &out)

        guard steps > 0 else {
            out += "}\n"
            return out
        }

        renderStepNodes(participants: participants, steps: steps, into: &out)
        renderLifelines(participants: participants, steps: steps, into: &out)
        renderMessages(messages, into: &out)

        out += "}\n"
        return out
    }

    // MARK: - Render Sections

    private func renderParticipantHeaders(
        _ participants: [SequenceDiagram.Participant],
        into out: inout String
    ) {
        out += "  // Participants\n"
        for p in participants {
            let nodeId = participantHeaderID(p.id)
            let stereotype = participantStereotype(p.kind)
            var label = p.name.dotHTMLEscaped
            if let s = stereotype { label = "&lt;&lt;\(s)&gt;&gt;\\n\(label)" }
            out += "  \(nodeId) [shape=box\(nodeColorAttrs) label=\"\(label)\"];\n"
        }
        if !participants.isEmpty {
            out += "  { rank=same; "
            out += participants.map { participantHeaderID($0.id) }.joined(separator: "; ")
            out += "; }\n\n"
        }
    }

    private func renderStepNodes(
        participants: [SequenceDiagram.Participant],
        steps: Int,
        into out: inout String
    ) {
        out += "  // Lifeline step nodes\n"
        out += "  node [shape=none label=\"\" width=0 height=0];\n"
        for step in 0..<steps {
            for p in participants {
                out += "  \(stepNodeID(p.id, step: step));\n"
            }
            out += "  { rank=same; "
            out += participants.map { stepNodeID($0.id, step: step) }.joined(separator: "; ")
            out += "; }\n"
        }
    }

    private func renderLifelines(
        participants: [SequenceDiagram.Participant],
        steps: Int,
        into out: inout String
    ) {
        out += "\n  // Lifelines\n"
        for p in participants {
            let chain = [participantHeaderID(p.id)]
                + (0..<steps).map { stepNodeID(p.id, step: $0) }
            for (a, b) in zip(chain, chain.dropFirst()) {
                out += "  \(a) -> \(b) [style=invis];\n"
            }
        }
    }

    private func renderMessages(_ messages: [SequenceDiagram.Message], into out: inout String) {
        out += "\n  // Messages\n"
        out += "  node [shape=none label=\"\"];\n"
        for (step, msg) in messages.enumerated() {
            let from = stepNodeID(msg.from, step: step)
            let to = stepNodeID(msg.to, step: step)
            var parts: [String] = []
            if let theme { parts.append("color=\"\(theme.edgeColor)\" fontcolor=\"\(theme.fontColor)\"") }
            if let lbl = msg.label { parts.append("label=\"\(lbl.dotEscaped)\"") }
            parts.append(arrowAttributes(for: msg.kind))
            out += "  \(from) -> \(to) [\(parts.joined(separator: " "))];\n"
        }
    }

    // MARK: - Helpers

    private func participantHeaderID(_ id: String) -> String { "\"\(id)_header\"" }
    private func stepNodeID(_ participantId: String, step: Int) -> String {
        "\"\(participantId)_step\(step)\""
    }

    private func participantStereotype(_ kind: SequenceDiagram.Participant.Kind) -> String? {
        switch kind {
        case .object:
            return nil
        case .actor:
            return "actor"
        case .boundary:
            return "boundary"
        case .control:
            return "control"
        case .entity:
            return "entity"
        case .database:
            return "database"
        }
    }

    private func arrowAttributes(for kind: SequenceDiagram.Message.Kind) -> String {
        switch kind {
        case .synchronous:
            return "arrowhead=normal style=solid"
        case .asynchronous:
            return "arrowhead=open style=solid"
        case .return:
            return "arrowhead=normal style=dashed"
        case .create:
            return "arrowhead=normal style=dashed label=\"<<create>>\""
        case .destroy:
            return "arrowhead=normal style=solid label=\"<<destroy>>\""
        }
    }

    private func graphAttributes() -> String {
        graphAttributes(rankdir: "TB")
    }
}
