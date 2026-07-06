import UMLCore

/// Builds the `ClassDiagram` model from a `CodeArtifact` for a set of display options.
///
/// This is a value you instantiate with the options and ask to `build(from:)` — deliberately *not* a
/// `CodeArtifact.classDiagram(...)` extension. Keeping the behaviour off the data model means the
/// agnostic `CodeArtifact` does not reference the diagram layer, which removes the
/// `ClassDiagram ↔ CodeArtifact` reference cycle (the model only ever depends downward onto
/// `CodeArtifact`, never back).
///
/// Building runs UMLCore enrichment once (extension resolution, name→id resolution, inferred
/// composition/aggregation/dependency edges, external detection, optional single-type focus).
/// Enrichment is idempotent, so building from an already-enriched artifact is a no-op. Build once and
/// render the result to any number of formats.
public struct ClassDiagramBuilder: Sendable {
    private let options: ClassDiagramOptions

    public init(options: ClassDiagramOptions) {
        self.options = options
    }

    public func build(from artifact: CodeArtifact) -> ClassDiagram {
        ClassDiagram(
            artifact: artifact,
            options: EnrichmentOptions(
                inferCompositionFromProperties: options.inferCompositionFromProperties,
                inferDependencyFromMethods: options.inferDependencyFromMethods,
                showExternalTypes: options.showExternalTypes,
                focus: options.focus,
                languages: options.languages
            )
        )
    }
}
