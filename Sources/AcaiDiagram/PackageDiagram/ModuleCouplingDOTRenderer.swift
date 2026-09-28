import Foundation

/// Renders a `PackageDiagram` to Graphviz DOT as Robert Martin's **coupling view**: the same module
/// nodes and weighted dependency edges `PackageDiagramDOTRenderer` draws, but labelled with the full
/// metric set (`Ca`/`Ce`/`I`/`A`/`D`) and the module's named main-sequence zone, with
/// Stable-Dependencies-Principle breaches drawn dashed.
///
/// The zone is spelled out in the label rather than left to the fill colour alone, so the view still
/// reads in a monochrome export or a terminal diff.
public struct ModuleCouplingDOTRenderer: DOTRenderer {
    public let renderOptions: DiagramRenderOptions

    /// Optional per-node border override (a hex, keyed on module id) — used to mark a delta
    /// diagram's added/removed modules, as in `PackageDiagramDOTRenderer`.
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

    public func render(_ diagram: PackageDiagram) -> String {
        var out = "digraph {\n"
        if let title = diagram.title {
            out += "  label=\"\(title.dotEscaped)\";\n"
            out += "  labelloc=t;\n"
        }
        out += graphAttributes()

        for node in diagram.nodes {
            out += "  \(node.id.dotNodeID) [label=\"\(nodeLabel(node).dotEscaped)\""
            out += " fillcolor=\"\(node.zoneColorHex)\""
            if let border = nodeColor?(node.id) { out += " color=\"\(border)\" penwidth=3" }
            out += "];\n"
        }

        let breaches = diagram.stableDependencyBreaches
        for edge in diagram.edges {
            let isBreach = breaches.contains(edge)
            var parts: [String] = []
            if let color = edgeColor?(edge.from, edge.to) ?? theme?.edgeColor {
                parts.append("color=\"\(color)\"")
            }
            parts.append("penwidth=\(penWidth(forWeight: edge.weight))")
            parts.append("label=\"\(edgeLabel(edge, isBreach: isBreach).dotEscaped)\"")
            if isBreach { parts.append("style=dashed") }
            out += "  \(edge.from.dotNodeID) -> \(edge.to.dotNodeID) [\(parts.joined(separator: " "))];\n"
        }

        out += "}\n"
        return out
    }

    // MARK: - Helpers

    private func nodeLabel(_ node: PackageDiagram.Node) -> String {
        let types = node.typeCount == 1 ? "1 type" : "\(node.typeCount) types"
        return """
            \(node.name)
            Ca=\(node.afferentCoupling)  Ce=\(node.efferentCoupling)
            I=\(twoDecimals(node.instability))  A=\(twoDecimals(node.abstractness))  \
            D=\(twoDecimals(node.distanceFromMainSequence))
            \(node.mainSequenceZone.label)
            \(types)
            """
    }

    private func edgeLabel(_ edge: PackageDiagram.Edge, isBreach: Bool) -> String {
        isBreach ? "\(edge.weight) (SDP)" : "\(edge.weight)"
    }

    private func twoDecimals(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// Maps an edge weight to a line width, clamped so heavy edges stay readable.
    private func penWidth(forWeight weight: Int) -> String {
        String(format: "%.1f", 1.0 + min(Double(weight) / 4.0, 4.0))
    }

    private func graphAttributes() -> String {
        let nodeColor = theme.map { " color=\"\($0.nodeBorderColor)\" fontcolor=\"\($0.fontColor)\"" } ?? ""
        return graphAttributes(
            rankdir: "LR",
            nodeDefaults: "shape=box style=\"rounded,filled\"\(nodeColor) "
        )
    }
}
