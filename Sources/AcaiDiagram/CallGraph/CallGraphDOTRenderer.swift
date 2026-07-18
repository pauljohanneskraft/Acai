/// Renders a `CallGraph` to Graphviz DOT.
///
/// Each method is a rounded box labelled `Type.method`; in-scope methods are filled solid,
/// out-of-scope callees are drawn dashed and lighter so the focus stands out. Edges carry the
/// call multiplicity when a caller hits the same target more than once.
public struct CallGraphDOTRenderer: DOTRenderer {
    public let renderOptions: DiagramRenderOptions

    /// Solid fill for methods inside the scope.
    private let inScopeFill = "#e3f2fd"
    /// Lighter fill for resolved callees pulled in from outside the scope.
    private let leafFill = "#f5f5f5"

    /// Optional per-node fill override (a hex, keyed on node id). When non-`nil` it replaces the
    /// in-scope/leaf fill — used to colour a delta diagram's added/removed methods.
    public let nodeColor: (@Sendable (String) -> String?)?
    /// Optional per-edge colour override (a hex, keyed on `(from, to)`). Wins over `theme.edgeColor`.
    public let edgeColor: (@Sendable (String, String) -> String?)?

    public init(
        theme: DiagramTheme? = nil,
        fontName: String = "Helvetica",
        fontSize: Int = 12,
        nodeColor: (@Sendable (String) -> String?)? = nil,
        edgeColor: (@Sendable (String, String) -> String?)? = nil
    ) {
        self.renderOptions = DiagramRenderOptions(theme: theme, fontName: fontName, fontSize: fontSize)
        self.nodeColor = nodeColor
        self.edgeColor = edgeColor
    }

    public func render(_ graph: CallGraph) -> String {
        var out = "digraph {\n"
        if let title = graph.title {
            out += "  label=\"\(title.dotEscaped)\";\n"
            out += "  labelloc=t;\n"
        }
        out += graphAttributes()

        for node in graph.nodes {
            var parts: [String] = ["label=\"\(node.label.dotEscaped)\""]
            parts.append("fillcolor=\"\(node.inScope ? inScopeFill : leafFill)\"")
            if !node.inScope {
                parts.append("style=\"rounded,filled,dashed\"")
            }
            // A delta override colours the node's *border* (keeping the in-scope/leaf fill).
            if let border = nodeColor?(node.id) { parts.append("color=\"\(border)\" penwidth=3") }
            out += "  \(node.id.dotNodeID) [\(parts.joined(separator: " "))];\n"
        }

        for edge in graph.edges {
            var parts: [String] = []
            if let color = edgeColor?(edge.from, edge.to) ?? theme?.edgeColor { parts.append("color=\"\(color)\"") }
            if edge.weight > 1 { parts.append("label=\"\(edge.weight)\"") }
            let attrs = parts.isEmpty ? "" : " [\(parts.joined(separator: " "))]"
            out += "  \(edge.from.dotNodeID) -> \(edge.to.dotNodeID)\(attrs);\n"
        }

        out += "}\n"
        return out
    }

    private func graphAttributes() -> String {
        let nodeColor = theme.map { " color=\"\($0.nodeBorderColor)\" fontcolor=\"\($0.fontColor)\"" } ?? ""
        return graphAttributes(
            rankdir: "LR",
            nodeDefaults: "shape=box style=\"rounded,filled\"\(nodeColor) "
        )
    }
}
