import UMLCore

public struct DOTGenerator: Sendable {
    private let options: DiagramOptions

    public init(options: DiagramOptions = DiagramOptions()) {
        self.options = options
    }

    public func generate(from artifact: CodeArtifact) -> String {
        // Enrich the artifact: flatten nested types, resolve relationships,
        // infer composition / aggregation / dependency edges, detect externals.
        let enriched = ClassDiagramEnricher.enrich(
            artifact,
            options: EnrichmentOptions(
                inferCompositionFromProperties: options.inferCompositionFromProperties,
                inferDependencyFromMethods: options.inferDependencyFromMethods,
                showExternalTypes: options.showExternalTypes
            )
        )

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
