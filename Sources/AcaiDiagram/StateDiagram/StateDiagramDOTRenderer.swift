/// Renders a `StateDiagram` to Graphviz DOT format.
///
/// States are DOT nodes with shape variants chosen by `State.Kind`.
/// Composite states are rendered as `subgraph` clusters.
/// Transitions become directed edges with `event [guard] / action` labels.
public struct StateDiagramDOTRenderer: DOTRenderer {
    public let renderOptions: DiagramRenderOptions

    /// Optional per-transition colour override (a hex like `#2e7d32`). When it returns a non-`nil`
    /// colour for a transition, that colour wins over `theme.edgeColor`; `nil` (or a `nil` closure)
    /// leaves colouring unchanged. Used to tint a delta diagram's added/removed transitions.
    /// Default `nil` keeps existing output byte-for-byte identical.
    public let transitionColor: (@Sendable (StateDiagram.Transition) -> String?)?

    public init(
        theme: DiagramTheme? = nil,
        fontName: String = "Helvetica",
        fontSize: Int = 12,
        transitionColor: (@Sendable (StateDiagram.Transition) -> String?)? = nil
    ) {
        self.renderOptions = DiagramRenderOptions(theme: theme, fontName: fontName, fontSize: fontSize)
        self.transitionColor = transitionColor
    }

    /// Cosmetic fill/border/font attributes for normal & choice states when themed, else empty.
    private var nodeColorAttrs: String {
        guard let theme else { return "" }
        return " style=filled fillcolor=\"\(theme.nodeFillColor)\""
            + " color=\"\(theme.nodeBorderColor)\" fontcolor=\"\(theme.fontColor)\""
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
        if let theme {
            out += "    color=\"\(theme.nodeBorderColor)\";\n"
            out += "    fontcolor=\"\(theme.fontColor)\";\n"
        }
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
        // The solid dot/bar of a pseudo-state is semantic (it *is* the marker), so it is always
        // filled: with the theme's border colour when themed (stays visible on the themed
        // background), else black (visible on the default white canvas).
        let marker = theme?.nodeBorderColor ?? "black"

        switch state.kind {
        case .initial:
            return "[shape=circle style=filled fillcolor=\"\(marker)\" width=0.3 label=\"\"]"

        case .final:
            return "[shape=circle style=filled fillcolor=\"\(marker)\" width=0.4 " +
                   "peripheries=2 label=\"\"]"

        case .choice:
            return "[shape=diamond\(nodeColorAttrs) label=\"\(state.name.dotHTMLEscaped)\"]"

        case .fork, .join:
            return "[shape=rect style=filled fillcolor=\"\(marker)\" width=1.5 height=0.15 label=\"\"]"

        case .normal, .composite:
            var label = state.name.dotHTMLEscaped
            if let entry = state.entryAction { label += "\\nentry/ \(entry.dotEscaped)" }
            if let doAct = state.doActivity { label += "\\ndo/ \(doAct.dotEscaped)" }
            if let exit  = state.exitAction { label += "\\nexit/ \(exit.dotEscaped)" }
            return "[shape=Mrecord\(nodeColorAttrs) label=\"\(label)\"]"
        }
    }

    // MARK: - Transition rendering

    private func renderTransitions(_ transitions: [StateDiagram.Transition]) -> String {
        transitions.map { t in
            let from = t.from.dotNodeID
            let to = t.to.dotNodeID
            var parts: [String] = []
            // A per-transition override wins over the theme edge colour; neither present ⇒ no
            // colour attribute (output unchanged).
            if let color = transitionColor?(t) ?? theme?.edgeColor { parts.append("color=\"\(color)\"") }
            if let lbl = t.label { parts.append("label=\"\(lbl.dotEscaped)\"") }
            let attrs = parts.isEmpty ? "" : " [\(parts.joined(separator: " "))]"
            return "  \(from) -> \(to)\(attrs);\n"
        }.joined()
    }

    // MARK: - Graph attributes

    private func graphAttributes() -> String {
        graphAttributes(rankdir: "TB")
    }
}
