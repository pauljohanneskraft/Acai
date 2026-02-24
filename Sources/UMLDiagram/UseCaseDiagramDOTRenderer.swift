import UMLCore

/// Renders a `UseCaseDiagram` to Graphviz DOT format.
///
/// Human actors are rendered as tall boxes with `<<actor>>` stereotype.
/// System actors use `<<system>>`.
/// Use cases are ellipses.
/// All use cases are optionally wrapped in a system-boundary subgraph cluster.
public struct UseCaseDiagramDOTRenderer: Sendable {
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
            let fill = theme.nodeFillColor
            let border = theme.nodeBorderColor
            let font = theme.fontColor
            let fs = fontSize
            let label = "<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\">" +
                        "<TR><TD><FONT POINT-SIZE=\"\(fs - 2)\" COLOR=\"\(font)\">" +
                        "&lt;&lt;\(stereotype)&gt;&gt;</FONT></TD></TR>" +
                        "<TR><TD><FONT COLOR=\"\(font)\">\(actor.name.dotHTMLEscaped)</FONT></TD></TR>" +
                        "</TABLE>"
            return "  \(nodeId) [label=<\(label)> shape=box style=\"rounded,filled\" " +
                   "fillcolor=\"\(fill)\" color=\"\(border)\"];\n"
        }.joined()
    }

    private func renderUseCases(_ useCases: [UseCaseDiagram.UseCase], boundary: String?) -> String {
        var out = ""
        if let label = boundary {
            out += "  subgraph cluster_system {\n"
            out += "    label=\"\(label.dotEscaped)\";\n"
            out += "    style=rounded;\n"
            out += "    color=\"\(theme.nodeBorderColor)\";\n"
            out += "    fontcolor=\"\(theme.fontColor)\";\n"
            out += useCases.map { renderUseCase($0, indent: "    ") }.joined()
            out += "  }\n"
        } else {
            out += useCases.map { renderUseCase($0, indent: "  ") }.joined()
        }
        return out
    }

    private func renderUseCase(_ uc: UseCaseDiagram.UseCase, indent: String) -> String {
        let nodeId = uc.id.dotNodeID
        let font = theme.fontColor
        let fill = theme.nodeFillColor
        let border = theme.nodeBorderColor
        return "\(indent)\(nodeId) [label=\"\(uc.name.dotEscaped)\" shape=ellipse " +
               "style=filled fillcolor=\"\(fill)\" color=\"\(border)\" fontcolor=\"\(font)\"];\n"
    }

    // MARK: - Edge rendering

    private func renderRelationships(_ relationships: [UseCaseDiagram.Relationship]) -> String {
        relationships.map { rel in
            let source = rel.source.dotNodeID
            let target = rel.target.dotNodeID
            let color = theme.edgeColor
            switch rel.kind {
            case .association:
                return "  \(source) -> \(target) [arrowhead=none color=\"\(color)\"];\n"
            case .include:
                return "  \(source) -> \(target) [style=dashed arrowhead=open " +
                       "label=\"<<include>>\" fontcolor=\"\(theme.fontColor)\" color=\"\(color)\"];\n"
            case .extend:
                var lbl = "<<extend>>"
                if let cond = rel.condition { lbl += "\\n[\(cond)]" }
                return "  \(source) -> \(target) [style=dashed arrowhead=open " +
                       "label=\"\(lbl.dotEscaped)\" fontcolor=\"\(theme.fontColor)\" color=\"\(color)\"];\n"
            case .generalization:
                return "  \(source) -> \(target) [arrowhead=empty style=solid color=\"\(color)\"];\n"
            }
        }.joined()
    }

    // MARK: - Graph attributes

    private func graphAttributes() -> String {
        """
          rankdir=LR;
          bgcolor="\(theme.backgroundColor)";
          compound=true;
          fontname="\(fontName)";
          fontsize=\(fontSize);
          node [fontname="\(fontName)" fontsize=\(fontSize)];
          edge [fontname="\(fontName)" fontsize=\(fontSize - 2)];

        """
    }
}
