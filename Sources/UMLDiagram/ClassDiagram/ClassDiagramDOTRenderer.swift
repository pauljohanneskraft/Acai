import UMLCore

public struct ClassDiagramDOTRenderer: DOTRenderer {
    private let options: ClassDiagramOptions

    public var renderOptions: DiagramRenderOptions {
        DiagramRenderOptions(theme: options.theme, fontName: options.fontName, fontSize: options.fontSize)
    }

    public init(options: ClassDiagramOptions) {
        self.options = options
    }

    /// Builds the `ClassDiagram` model from `artifact`, then renders it.
    public func generate(from artifact: CodeArtifact) -> String {
        generate(from: ClassDiagramBuilder(options: options).build(from: artifact))
    }

    /// Renders a pre-built `ClassDiagram` model (built once via `CodeArtifact.classDiagram`).
    public func generate(from enriched: ClassDiagram) -> String {
        let nodeRenderer = DOTNodeRenderer(options: options)
        let edgeRenderer = DOTEdgeRenderer(options: options)
        let clusterRenderer = DOTClusterRenderer(options: options)

        var output = "digraph UML {\n"
        output += graphAttributes()

        switch options.groupBy {
        case .none:
            output += nodeRenderer.render(types: enriched.types)
        case .byFile:
            output += clusterRenderer.renderByFile(types: enriched.types)
        case .byNamespace:
            output += clusterRenderer.renderByNamespace(types: enriched.types)
        case .byDirectory:
            output += clusterRenderer.renderByDirectory(
                types: enriched.types,
                directoryGroups: enriched.directoryGroups
            )
        }

        // Render external dependency nodes (light gray placeholders).
        if !enriched.externalTypes.isEmpty {
            output += nodeRenderer.renderExternal(types: enriched.externalTypes)
        }

        output += edgeRenderer.render(relationships: enriched.relationships)
        output += "}\n"
        return output
    }

    private func graphAttributes() -> String {
        graphAttributes(
            rankdir: options.layoutDirection.rawValue,
            compound: true,
            nodeDefaults: "shape=none margin=0 "
        )
    }
}
