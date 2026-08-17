import AcaiCore

/// Builds the `ClassDiagram` model from a `CodeArtifact` for a set of display options.
///
/// A value you instantiate with the options and ask to `build(from:)` — deliberately not a
/// `CodeArtifact.classDiagram(...)` extension, so the agnostic `CodeArtifact` never references the
/// diagram layer back.
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
