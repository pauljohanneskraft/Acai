import Foundation
import AcaiCore

protocol CodebaseAnalyzing: Sendable {
    func enrichedArtifact(at url: URL, fileFilter: FileFilter?) throws -> CodeArtifact
}

/// A codebase only gets `FixtureCodebaseAnalyzer` if the launch staged a canned artifact for it
/// specifically — a journey that stages none still gets the real analyzer.
struct CodebaseAnalyzingResolver {
    func resolve(codebaseID: UUID) -> CodebaseAnalyzing {
        guard UITestFixtureResolver().resolveBaseDir() != nil else { return CodebaseAnalyzer() }
        guard let artifactURL = UITestFixtureResolver().resolveCodebaseArtifactURLs()[codebaseID] else {
            return CodebaseAnalyzer()
        }
        return FixtureCodebaseAnalyzer(artifactURL: artifactURL)
    }
}
