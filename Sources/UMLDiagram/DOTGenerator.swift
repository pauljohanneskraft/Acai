import UMLCore

public struct DOTGenerator: Sendable {
    private let options: DiagramOptions

    public init(options: DiagramOptions = DiagramOptions()) {
        self.options = options
    }

    public func generate(from artifact: CodeArtifact) -> String {
        let nodeRenderer = DOTNodeRenderer(options: options)
        let edgeRenderer = DOTEdgeRenderer(options: options)
        let clusterRenderer = DOTClusterRenderer(options: options)

        var output = "digraph UML {\n"
        output += graphAttributes()

        switch options.groupBy {
        case .none:
            output += nodeRenderer.render(types: artifact.types)
        case .byFile:
            output += clusterRenderer.renderByFile(types: artifact.types)
        case .byNamespace:
            output += clusterRenderer.renderByNamespace(types: artifact.types)
        }

        output += edgeRenderer.render(relationships: artifact.relationships)
        output += "}\n"
        return output
    }

    private func graphAttributes() -> String {
        """
          rankdir=\(options.layoutDirection.rawValue);
          bgcolor="\(options.theme.backgroundColor)";
          compound=true;
          fontname="\(options.fontName)";
          fontsize=\(options.fontSize);
          node [shape=none margin=0 fontname="\(options.fontName)" fontsize=\(options.fontSize)];
          edge [fontname="\(options.fontName)" fontsize=\(options.fontSize - 2)];

        """
    }
}
