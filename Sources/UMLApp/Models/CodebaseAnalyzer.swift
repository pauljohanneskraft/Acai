import Foundation
import UMLCore
import UMLDiagram
import UMLLibrary

/// Analyzes a source directory into the enriched `CodeArtifact` the app stores and renders. Owns
/// the exact analyze-then-enrich pipeline used for reindexing, so any other producer of an artifact
/// (e.g. a git-revision snapshot for delta mode) yields a like-for-like artifact that diffs cleanly.
struct CodebaseAnalyzer {
    let service: AnalysisService

    init(service: AnalysisService = .standard) {
        self.service = service
    }

    /// Analyzes the directory at `url` and applies the standard class-diagram enrichment
    /// (composition/dependency inference, external types), returning the artifact to store.
    func enrichedArtifact(at url: URL) throws -> CodeArtifact {
        let artifact = try service.analyzeProject(at: url, allowedLanguages: [])
        let enriched = ClassDiagram(
            artifact: artifact,
            options: EnrichmentOptions(
                inferCompositionFromProperties: true,
                inferDependencyFromMethods: true,
                showExternalTypes: true,
                languages: artifact.standardLanguageResolver
            )
        )
        return CodeArtifact(
            metadata: artifact.metadata,
            types: enriched.types,
            relationships: enriched.relationships,
            freestandingFunctions: artifact.freestandingFunctions
        )
    }
}
