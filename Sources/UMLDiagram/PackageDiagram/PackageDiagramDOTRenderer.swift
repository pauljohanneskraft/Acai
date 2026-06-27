import Foundation

/// Renders a `PackageDependencyDiagram` to Graphviz DOT.
///
/// Each module is a rounded box labelled with its name and coupling metrics
/// (`I` = instability, `A` = abstractness, plus the type count). The fill colour
/// encodes the module's distance from the main sequence — green (balanced) through
/// amber to red (deep in the zone of pain / uselessness). Edges are weighted by the
/// number of cross-module references (thicker = more coupling).
public struct PackageDiagramDOTRenderer: DOTRenderer {
    public let renderOptions: DiagramRenderOptions

    /// Optional per-node fill override (a hex, keyed on module id). When non-`nil` it replaces the
    /// node's `zoneColorHex` tint — used to colour a delta diagram's added/removed modules.
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

    public func render(_ diagram: PackageDependencyDiagram) -> String {
        var out = "digraph {\n"
        if let title = diagram.title {
            out += "  label=\"\(title.dotEscaped)\";\n"
            out += "  labelloc=t;\n"
        }
        out += graphAttributes()

        for node in diagram.nodes {
            out += "  \(node.id.dotNodeID) [label=\"\(nodeLabel(node).dotEscaped)\""
            // Keep the distance-zone fill; a delta override colours the *border* instead.
            out += " fillcolor=\"\(node.zoneColorHex)\""
            if let border = nodeColor?(node.id) { out += " color=\"\(border)\" penwidth=3" }
            out += "];\n"
        }

        for edge in diagram.edges {
            var parts: [String] = []
            if let color = edgeColor?(edge.from, edge.to) ?? theme?.edgeColor {
                parts.append("color=\"\(color)\"")
            }
            parts.append("penwidth=\(penWidth(forWeight: edge.weight))")
            parts.append("label=\"\(edge.weight)\"")
            out += "  \(edge.from.dotNodeID) -> \(edge.to.dotNodeID) [\(parts.joined(separator: " "))];\n"
        }

        out += "}\n"
        return out
    }

    // MARK: - Helpers

    private func nodeLabel(_ node: PackageDependencyDiagram.Node) -> String {
        let instability = String(format: "%.2f", node.instability)
        let abstractness = String(format: "%.2f", node.abstractness)
        let types = node.typeCount == 1 ? "1 type" : "\(node.typeCount) types"
        return "\(node.name)\nI=\(instability)  A=\(abstractness)\n\(types)"
    }

    /// Maps an edge weight to a line width, clamped so heavy edges stay readable.
    private func penWidth(forWeight weight: Int) -> String {
        let width = 1.0 + min(Double(weight) / 4.0, 4.0)
        return String(format: "%.1f", width)
    }

    private func graphAttributes() -> String {
        let nodeColor = theme.map { " color=\"\($0.nodeBorderColor)\" fontcolor=\"\($0.fontColor)\"" } ?? ""
        return graphAttributes(
            rankdir: "LR",
            nodeDefaults: "shape=box style=\"rounded,filled\"\(nodeColor) "
        )
    }
}
