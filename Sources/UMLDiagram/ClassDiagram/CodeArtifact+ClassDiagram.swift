import UMLCore

/// The built class-diagram model: enriched types, resolved relationships, external
/// placeholders and directory groups, ready to hand to a renderer. Named to match the
/// `SequenceDiagram` / `StateDiagram` / `PackageDependencyDiagram` models so every diagram
/// type follows the same "extract a model, render the model" shape.
public typealias ClassDiagram = ClassDiagramEnricher.Result

extension CodeArtifact {

    /// Derives the `ClassDiagram` model for the given options.
    ///
    /// Runs `ClassDiagramEnricher` once (extension resolution, name→id resolution, inferred
    /// composition/aggregation/dependency edges, external detection, optional single-type
    /// focus). Enrichment is idempotent, so calling this on an already-enriched artifact is a
    /// no-op. Renderers take the result so a class diagram is built once and rendered to any
    /// number of formats — matching `sequenceDiagram`/`stateDiagram`/`packageDependencyDiagram`.
    public func classDiagram(options: ClassDiagramOptions = ClassDiagramOptions()) -> ClassDiagram {
        ClassDiagramEnricher.enrich(
            self,
            options: EnrichmentOptions(
                inferCompositionFromProperties: options.inferCompositionFromProperties,
                inferDependencyFromMethods: options.inferDependencyFromMethods,
                showExternalTypes: options.showExternalTypes,
                focus: options.focus
            )
        )
    }
}
