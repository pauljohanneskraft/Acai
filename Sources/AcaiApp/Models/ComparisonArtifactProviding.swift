import AcaiCore
import Foundation

protocol ComparisonArtifactProviding: Sendable {
    func artifact(analyzer: CodebaseAnalyzing, fileFilter: FileFilter?) throws -> CodeArtifact
}

extension GitRevisionSnapshot: ComparisonArtifactProviding {}

/// Decodes a pre-baked `CodeArtifact` JSON directly instead of extracting a real git tree —
/// mirrors `FixtureCodebaseAnalyzer`'s plain (unwrapped) decode.
struct FixtureComparisonArtifact: ComparisonArtifactProviding {
    let artifactURL: URL

    func artifact(analyzer: CodebaseAnalyzing, fileFilter: FileFilter?) throws -> CodeArtifact {
        let data = try Data(contentsOf: artifactURL)
        return try JSONDecoder().decode(CodeArtifact.self, from: data)
    }
}

/// A `(codebaseID, ref)` pair only gets `FixtureComparisonArtifact` if the launch staged a canned
/// comparison artifact for it specifically — an unstaged pair still gets the real `GitRevisionSnapshot`.
struct ComparisonArtifactResolver {
    func resolve(codebaseID: UUID, ref: String, directory: URL) -> ComparisonArtifactProviding {
        guard UITestFixtureResolver().resolveBaseDir() != nil else {
            return GitRevisionSnapshot(directory: directory, reference: ref)
        }
        let key = UITestFixtureResolver.ComparisonArtifactKey(codebaseID: codebaseID, ref: ref)
        guard let artifactURL = UITestFixtureResolver().resolveComparisonArtifactURLs()[key] else {
            return GitRevisionSnapshot(directory: directory, reference: ref)
        }
        return FixtureComparisonArtifact(artifactURL: artifactURL)
    }
}
