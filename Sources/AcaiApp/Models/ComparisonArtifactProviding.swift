import AcaiCore
import Foundation

protocol ComparisonArtifactProviding: Sendable {
    func artifact(analyzer: CodebaseAnalyzing, fileFilter: FileFilter?) async throws -> CodeArtifact
}

extension GitRevisionSnapshot: ComparisonArtifactProviding {}

/// Decodes a pre-baked `CodeArtifact` JSON directly instead of extracting a real git tree —
/// mirrors `FixtureCodebaseAnalyzer`'s plain (unwrapped) decode.
struct FixtureComparisonArtifact: ComparisonArtifactProviding {
    let artifactURL: URL

    func artifact(analyzer: CodebaseAnalyzing, fileFilter: FileFilter?) async throws -> CodeArtifact {
        let data = try Data(contentsOf: artifactURL)
        return try JSONDecoder().decode(CodeArtifact.self, from: data)
    }
}

protocol ComparisonArtifactSourcing: Sendable {
    func provider(codebaseID: UUID, ref: String, directory: URL) -> ComparisonArtifactProviding
}

/// A `(codebaseID, ref)` pair only gets `FixtureComparisonArtifact` if the launch staged a canned
/// comparison artifact for it specifically — an unstaged pair still gets the real `GitRevisionSnapshot`.
struct ComparisonArtifactResolver: ComparisonArtifactSourcing {
    var fixtures = UITestFixtureResolver()

    func provider(codebaseID: UUID, ref: String, directory: URL) -> ComparisonArtifactProviding {
        let key = UITestFixtureResolver.ComparisonArtifactKey(codebaseID: codebaseID, ref: ref)
        guard fixtures.resolveBaseDir() != nil, let artifactURL = fixtures.resolveComparisonArtifactURLs()[key] else {
            return GitRevisionSnapshot(directory: directory, reference: ref)
        }
        return FixtureComparisonArtifact(artifactURL: artifactURL)
    }
}
