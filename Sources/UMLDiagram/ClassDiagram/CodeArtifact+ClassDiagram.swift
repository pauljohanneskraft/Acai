import UMLCore

extension CodeArtifact {

    /// Derives the `ClassDiagram` model for the given options.
    ///
    /// Building the model runs UMLCore enrichment once (extension resolution, name→id resolution,
    /// inferred composition/aggregation/dependency edges, external detection, optional single-type
    /// focus). Enrichment is idempotent, so calling this on an already-enriched artifact is a no-op.
    /// Renderers take the result so a class diagram is built once and rendered to any number of
    /// formats — matching `sequenceDiagram`/`stateDiagram`/`packageDependencyDiagram`.
    public func classDiagram(options: ClassDiagramOptions) -> ClassDiagram {
        ClassDiagram(
            artifact: self,
            options: EnrichmentOptions(
                inferCompositionFromProperties: options.inferCompositionFromProperties,
                inferDependencyFromMethods: options.inferDependencyFromMethods,
                showExternalTypes: options.showExternalTypes,
                focus: options.focus,
                language: options.language
            )
        )
    }
}
