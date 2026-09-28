import Foundation
import AcaiCore

protocol CodebaseAnalyzing: Sendable {
    func enrichedArtifact(at url: URL, fileFilter: FileFilter?) async throws -> CodeArtifact
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
