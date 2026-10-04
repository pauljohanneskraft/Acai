import Foundation
import AcaiCore

protocol CodebaseAnalyzing: Sendable {
    func enrichedArtifact(at url: URL, fileFilter: FileFilter?, reusing cache: AnalysisCache) async throws
        -> CodeArtifact
}

extension CodebaseAnalyzing {
    /// Analyzes with nothing carried over from an earlier pass. The right call for a tree that will
    /// not be analyzed again — a git revision extracted to a temporary directory, say, where a
    /// persisted per-file cache would be written under a path nothing ever looks up again.
    func enrichedArtifact(at url: URL, fileFilter: FileFilter? = nil) async throws -> CodeArtifact {
        try await enrichedArtifact(at: url, fileFilter: fileFilter, reusing: .disabled)
    }
}

protocol CodebaseAnalyzerProviding: Sendable {
    func analyzer(for codebaseID: UUID) -> CodebaseAnalyzing
}

/// A UI test's canned artifact for this codebase, else its default canned artifact, else the real
/// analyzer — so a journey that stages nothing still parses for real.
struct CodebaseAnalyzingResolver: CodebaseAnalyzerProviding {
    var fixtures = UITestFixtureResolver()

    func analyzer(for codebaseID: UUID) -> CodebaseAnalyzing {
        guard fixtures.resolveBaseDir() != nil,
              let artifactURL = fixtures.resolveCodebaseArtifactURLs()[codebaseID]
                ?? fixtures.resolveDefaultCodebaseArtifactURL()
        else { return CodebaseAnalyzer() }
        return FixtureCodebaseAnalyzer(artifactURL: artifactURL)
    }
}
