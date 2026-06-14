import UMLCore

/// Renders a `UseCaseDiagram` to Graphviz DOT format.
///
/// Human actors are rendered as tall boxes with `<<actor>>` stereotype.
/// System actors use `<<system>>`.
/// Use cases are ellipses.
/// All use cases are optionally wrapped in a system-boundary subgraph cluster.
public struct UseCaseDiagramDOTRenderer: Sendable {
    public let theme: DiagramTheme?
    public let fontName: String
    public let fontSize: Int

    public init(
        theme: DiagramTheme? = nil,
        fontName: String = "Helvetica",
        fontSize: Int = 12
    ) {
        self.theme = theme
        self.fontName = fontName
        self.fontSize = fontSize
    }

    /// `COLOR="…"` fragment for a `<FONT>` tag, empty when unthemed.
    private func colorAttr(_ color: String?) -> String { color.map { " COLOR=\"\($0)\"" } ?? "" }
    private func fontOpen(_ color: String?) -> String { color.map { "<FONT COLOR=\"\($0)\">" } ?? "" }
    private func fontClose(_ color: String?) -> String { color != nil ? "</FONT>" : "" }

    // MARK: - Public API

    public func render(_ diagram: UseCaseDiagram) -> String {
        var out = "digraph {\n"
        if let title = diagram.title {
            out += "  label=\"\(title.dotEscaped)\";\n"
            out += "  labelloc=t;\n"
        }
        out += graphAttributes()
        out += renderActors(diagram.actors)
        out += renderUseCases(diagram.useCases, boundary: diagram.systemBoundaryLabel)
        out += renderRelationships(diagram.relationships)
        out += "}\n"
        return out
    }

    // MARK: - Node rendering

    private func renderActors(_ actors: [UseCaseDiagram.Actor]) -> String {
        actors.map { actor in
            let nodeId = actor.id.dotNodeID
            let stereotype = actor.isSystem ? "system" : "actor"
            let font = theme?.fontColor
            let label = "<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\">" +
                        "<TR><TD><FONT POINT-SIZE=\"\(fontSize - 2)\"\(colorAttr(font))>" +
                        "&lt;&lt;\(stereotype)&gt;&gt;</FONT></TD></TR>" +
                        "<TR><TD>\(fontOpen(font))\(actor.name.dotHTMLEscaped)\(fontClose(font))</TD></TR>" +
                        "</TABLE>"
            var style = ""
            if let theme {
                style = " style=\"rounded,filled\" fillcolor=\"\(theme.nodeFillColor)\""
                    + " color=\"\(theme.nodeBorderColor)\""
            }
            return "  \(nodeId) [label=<\(label)> shape=box\(style)];\n"
        }.joined()
    }

    private func renderUseCases(_ useCases: [UseCaseDiagram.UseCase], boundary: String?) -> String {
        var out = ""
        if let label = boundary {
            out += "  subgraph cluster_system {\n"
            out += "    label=\"\(label.dotEscaped)\";\n"
            out += "    style=rounded;\n"
            if let theme {
                out += "    color=\"\(theme.nodeBorderColor)\";\n"
                out += "    fontcolor=\"\(theme.fontColor)\";\n"
            }
            out += useCases.map { renderUseCase($0, indent: "    ") }.joined()
            out += "  }\n"
        } else {
            out += useCases.map { renderUseCase($0, indent: "  ") }.joined()
        }
        return out
    }

    private func renderUseCase(_ uc: UseCaseDiagram.UseCase, indent: String) -> String {
        let nodeId = uc.id.dotNodeID
        var style = ""
        if let theme {
            style = " style=filled fillcolor=\"\(theme.nodeFillColor)\""
                + " color=\"\(theme.nodeBorderColor)\" fontcolor=\"\(theme.fontColor)\""
        }
        return "\(indent)\(nodeId) [label=\"\(uc.name.dotEscaped)\" shape=ellipse\(style)];\n"
    }

    // MARK: - Edge rendering

    private func renderRelationships(_ relationships: [UseCaseDiagram.Relationship]) -> String {
        let colorAttr = theme.map { " color=\"\($0.edgeColor)\"" } ?? ""
        let fontAttr = theme.map { " fontcolor=\"\($0.fontColor)\"" } ?? ""
        return relationships.map { rel in
            let source = rel.source.dotNodeID
            let target = rel.target.dotNodeID
            switch rel.kind {
            case .association:
                return "  \(source) -> \(target) [arrowhead=none\(colorAttr)];\n"
            case .include:
                return "  \(source) -> \(target) [style=dashed arrowhead=open " +
                       "label=\"<<include>>\"\(fontAttr)\(colorAttr)];\n"
            case .extend:
                var lbl = "<<extend>>"
                if let cond = rel.condition { lbl += "\\n[\(cond)]" }
                return "  \(source) -> \(target) [style=dashed arrowhead=open " +
                       "label=\"\(lbl.dotEscaped)\"\(fontAttr)\(colorAttr)];\n"
            case .generalization:
                return "  \(source) -> \(target) [arrowhead=empty style=solid\(colorAttr)];\n"
            }
        }.joined()
    }

    // MARK: - Graph attributes

    private func graphAttributes() -> String {
        let background = theme.map { "  bgcolor=\"\($0.backgroundColor)\";\n" } ?? ""
        return """
          rankdir=LR;
        \(background)  compound=true;
          fontname="\(fontName)";
          fontsize=\(fontSize);
          node [fontname="\(fontName)" fontsize=\(fontSize)];
          edge [fontname="\(fontName)" fontsize=\(fontSize - 2)];

        """
    }
}
