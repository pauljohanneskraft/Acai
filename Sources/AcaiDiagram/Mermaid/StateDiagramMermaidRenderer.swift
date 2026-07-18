/// Renders a `StateDiagram` to a Mermaid `stateDiagram-v2`.
///
/// `initial` and `final` states map to Mermaid's `[*]` start/end pseudo-state;
/// other states are declared with a stable id and a display label. Composite
/// sub-states are flattened (the value-flow analyser does not currently emit them).
public struct StateDiagramMermaidRenderer: MermaidRenderer {
    public let theme: DiagramTheme?

    public init(theme: DiagramTheme? = nil) {
        self.theme = theme
    }

    public func render(_ diagram: StateDiagram) -> String {
        var lines: [String] = themePreamble
        lines.append("stateDiagram-v2")

        var allocator = MermaidIDAllocator()
        var refMap: [String: String] = [:]
        for state in diagram.states {
            switch state.kind {
            case .initial, .final:
                refMap[state.id] = "[*]"
            default:
                let safe = allocator.id(for: state.id)
                refMap[state.id] = safe
                lines.append("    state \"\(state.name.mermaidLabelEscaped)\" as \(safe)")
            }
        }

        for transition in diagram.transitions {
            guard let from = refMap[transition.from], let to = refMap[transition.to] else { continue }
            var line = "    \(from) --> \(to)"
            if let label = transition.label {
                line += " : \(label.mermaidTextEscaped)"
            }
            lines.append(line)
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
