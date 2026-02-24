import UMLCore

/// Renders a `StateDiagram` to Graphviz DOT format.
///
/// States are DOT nodes with shape variants chosen by `State.Kind`.
/// Composite states are rendered as `subgraph` clusters.
/// Transitions become directed edges with `event [guard] / action` labels.
public struct StateDiagramDOTRenderer: Sendable {
    public let theme: DiagramTheme
    public let fontName: String
    public let fontSize: Int

    public init(
        theme: DiagramTheme = .default,
        fontName: String = "Helvetica",
        fontSize: Int = 12
    ) {
        self.theme = theme
        self.fontName = fontName
        self.fontSize = fontSize
    }

    // MARK: - Public API

    public func render(_ diagram: StateDiagram) -> String {
        var out = "digraph {\n"
        if let title = diagram.title {
            out += "  label=\"\(title.dotEscaped)\";\n"
            out += "  labelloc=t;\n"
        }
        out += graphAttributes()
        out += renderStates(diagram.states, clusterIndex: 0).output
        out += renderTransitions(diagram.transitions)
        out += "}\n"
        return out
    }

    // MARK: - State rendering

    /// Returns rendered DOT text and the next available cluster index.
    private func renderStates(_ states: [StateDiagram.State], clusterIndex: Int) -> (output: String, nextIndex: Int) {
        var out = ""
        var index = clusterIndex
        for state in states {
            if state.kind == .composite && !state.substates.isEmpty {
                let (sub, next) = renderComposite(state, clusterIndex: index)
                out += sub
                index = next
            } else {
                out += renderState(state)
            }
        }
        return (out, index)
    }

    private func renderComposite(_ state: StateDiagram.State, clusterIndex: Int) -> (output: String, nextIndex: Int) {
        var out = "  subgraph cluster_\(clusterIndex) {\n"
        out += "    label=\"\(state.name.dotEscaped)\";\n"
        out += "    style=rounded;\n"
        out += "    color=\"\(theme.nodeBorderColor)\";\n"
        out += "    fontcolor=\"\(theme.fontColor)\";\n"
        let (sub, next) = renderStates(state.substates, clusterIndex: clusterIndex + 1)
        out += sub.split(separator: "\n").map { "  " + $0 }.joined(separator: "\n") + "\n"
        out += "  }\n"
        return (out, next)
    }

    private func renderState(_ state: StateDiagram.State) -> String {
        let nodeId = state.id.dotNodeID
        let attrs = nodeAttributes(for: state)
        return "  \(nodeId) \(attrs);\n"
    }

    private func nodeAttributes(for state: StateDiagram.State) -> String {
        let fill = theme.nodeFillColor
        let border = theme.nodeBorderColor
        let font = theme.fontColor

        switch state.kind {
        case .initial:
            return "[shape=circle style=filled fillcolor=\"\(border)\" width=0.3 label=\"\"]"

        case .final:
            return "[shape=circle style=filled fillcolor=\"\(border)\" width=0.4 " +
                   "peripheries=2 label=\"\"]"

        case .choice:
            return "[shape=diamond style=filled fillcolor=\"\(fill)\" color=\"\(border)\" " +
                   "fontcolor=\"\(font)\" label=\"\(state.name.dotHTMLEscaped)\"]"

        case .fork, .join:
            return "[shape=rect style=filled fillcolor=\"\(border)\" width=1.5 height=0.15 label=\"\"]"

        case .normal, .composite:
            var label = state.name.dotHTMLEscaped
            if let entry = state.entryAction { label += "\\nentry/ \(entry.dotEscaped)" }
            if let doAct = state.doActivity  { label += "\\ndo/ \(doAct.dotEscaped)" }
            if let exit  = state.exitAction  { label += "\\nexit/ \(exit.dotEscaped)" }
            return "[shape=Mrecord style=filled fillcolor=\"\(fill)\" color=\"\(border)\" " +
                   "fontcolor=\"\(font)\" label=\"\(label)\"]"
        }
    }

    // MARK: - Transition rendering

    private func renderTransitions(_ transitions: [StateDiagram.Transition]) -> String {
        transitions.map { t in
            let from = t.from.dotNodeID
            let to = t.to.dotNodeID
            let color = theme.edgeColor
            var attrs = "color=\"\(color)\""
            if let lbl = t.label {
                attrs += " label=\"\(lbl.dotEscaped)\""
            }
            return "  \(from) -> \(to) [\(attrs)];\n"
        }.joined()
    }

    // MARK: - Graph attributes

    private func graphAttributes() -> String {
        """
          rankdir=TB;
          bgcolor="\(theme.backgroundColor)";
          fontname="\(fontName)";
          fontsize=\(fontSize);
          node [fontname="\(fontName)" fontsize=\(fontSize)];
          edge [fontname="\(fontName)" fontsize=\(fontSize - 2)];

        """
    }
}
