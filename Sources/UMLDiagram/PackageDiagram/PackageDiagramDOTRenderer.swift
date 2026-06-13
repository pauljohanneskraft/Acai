import Foundation

/// Renders a `PackageDependencyDiagram` to Graphviz DOT.
///
/// Each module is a rounded box labelled with its name and coupling metrics
/// (`I` = instability, `A` = abstractness, plus the type count). The fill colour
/// encodes the module's distance from the main sequence — green (balanced) through
/// amber to red (deep in the zone of pain / uselessness). Edges are weighted by the
/// number of cross-module references (thicker = more coupling).
public struct PackageDiagramDOTRenderer: Sendable {
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

    public func render(_ diagram: PackageDependencyDiagram) -> String {
        var out = "digraph {\n"
        if let title = diagram.title {
            out += "  label=\"\(title.dotEscaped)\";\n"
            out += "  labelloc=t;\n"
        }
        out += graphAttributes()

        for node in diagram.nodes {
            out += "  \(node.id.dotNodeID) [label=\"\(nodeLabel(node).dotEscaped)\""
            out += " fillcolor=\"\(node.zoneColorHex)\"];\n"
        }

        for edge in diagram.edges {
            var attrs = "color=\"\(theme.edgeColor)\" penwidth=\(penWidth(forWeight: edge.weight))"
            attrs += " label=\"\(edge.weight)\""
            out += "  \(edge.from.dotNodeID) -> \(edge.to.dotNodeID) [\(attrs)];\n"
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
        """
          rankdir=LR;
          bgcolor="\(theme.backgroundColor)";
          fontname="\(fontName)";
          fontsize=\(fontSize);
          node [shape=box style="rounded,filled" color="\(theme.nodeBorderColor)" \
        fontcolor="\(theme.fontColor)" fontname="\(fontName)" fontsize=\(fontSize)];
          edge [fontname="\(fontName)" fontsize=\(fontSize - 2)];

        """
    }
}
