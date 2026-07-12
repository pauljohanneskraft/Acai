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

    /// Analyzes the directory at `url` into the **semantic** artifact the app stores. This is exactly
    /// the artifact `AnalysisService.analyzeProject` returns — already enriched (each language group
    /// resolved via `enriched(configuration:)`) and with nested types **preserved** so metrics that
    /// read the nested-type tree (e.g. nesting depth) are correct. It is stored verbatim, with no
    /// further whole-artifact `enriched(using:)` pass, so the app computes metrics / parse-health /
    /// scans on the **same** artifact the CLI (`uml metrics`) and MCP tools do — re-enriching here
    /// would re-append diagnostics and diverge from those. The diagram/detail layer flattens (and
    /// whole-artifact-enriches, via `ClassDiagram`) on demand in ``flattenedForDisplay(_:)``.
    func enrichedArtifact(at url: URL) throws -> CodeArtifact {
        try service.analyzeProject(at: url, allowedLanguages: [])
    }

    /// Flattens a stored semantic artifact into the diagram-ready form the views render from:
    /// nested types are hoisted to the top level with qualified display names and edges are
    /// re-resolved to the flattened ids. Idempotent, so an already-flat (pre-migration) artifact
    /// passes through unchanged.
    func flattenedForDisplay(_ semantic: CodeArtifact) -> CodeArtifact {
        let diagram = ClassDiagram(
            artifact: semantic,
            options: EnrichmentOptions(
                inferCompositionFromProperties: true,
                inferDependencyFromMethods: true,
                showExternalTypes: true,
                languages: semantic.standardLanguageResolver
            )
        )
        return CodeArtifact(
            metadata: semantic.metadata,
            types: diagram.types,
            relationships: diagram.relationships,
            freestandingFunctions: semantic.freestandingFunctions,
            globalVariables: semantic.globalVariables
        )
    }
}
