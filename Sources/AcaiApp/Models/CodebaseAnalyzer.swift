import Foundation
import AcaiCore
import AcaiDiagram
import AcaiLibrary

/// Owns the exact analyze-then-enrich pipeline used for reindexing, so any other producer of an
/// artifact (e.g. a git-revision snapshot for delta mode) yields a like-for-like artifact that
/// diffs cleanly.
struct CodebaseAnalyzer: CodebaseAnalyzing {
    let service: AnalysisService

    init(service: AnalysisService = .standard) {
        self.service = service
    }

    /// Stored verbatim, with no further whole-artifact `enriched(using:)` pass, so the app computes
    /// metrics / parse-health / scans on the **same** artifact the CLI (`acai metrics`) and MCP
    /// tools do — re-enriching here would re-append diagnostics and diverge from those.
    func enrichedArtifact(at url: URL, fileFilter: FileFilter? = nil) throws -> CodeArtifact {
        try service.analyzeProject(at: url, allowedLanguages: []) { relativePath in
            fileFilter?.includes(relativePath) ?? true
        }
    }

    /// Idempotent, so an already-flat (pre-migration) artifact passes through unchanged.
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
