import Foundation
import AcaiCore

/// Indexing a UI test launch's codebases from a canned artifact, so a journey that needs an indexed
/// codebase starts on one instead of tapping Reindex and waiting.
extension ProjectStore {
    struct FixturePreindex: Sendable {
        let codebaseID: UUID
        let projectID: UUID
        let sourcePath: String
        let artifact: CodeArtifact
    }

    /// Fingerprints the source tree off the main actor, as `CodebaseFreshnessChecker`'s own doc comment
    /// requires — `currentFingerprint()` walks every file of a directory that isn't a git checkout, which
    /// no UI test fixture is. `lastIndexed` is fixed so the date this puts on screen is the same in every
    /// run; a reindex that landed while this was in flight wins, rather than being overwritten.
    func preindex(_ fixture: FixturePreindex) async {
        let store = analysisStore
        let sourcePath = fixture.sourcePath
        let artifact = fixture.artifact
        let fingerprint: CodeStateFingerprint? = await Task.detached(priority: .utility) {
            let fingerprint = CodebaseFreshnessChecker(directoryPath: sourcePath).currentFingerprint()
            guard (try? store.write(artifact, sourcePath: sourcePath, fingerprint: fingerprint)) != nil
            else { return nil }
            return fingerprint
        }.value
        guard let fingerprint,
              let pIndex = projects.firstIndex(where: { $0.id == fixture.projectID }),
              let cIndex = projects[pIndex].codebases.firstIndex(where: { $0.id == fixture.codebaseID }),
              !projects[pIndex].codebases[cIndex].hasArtifact
        else { return }
        projects[pIndex].codebases[cIndex].hasArtifact = true
        projects[pIndex].codebases[cIndex].lastIndexed = Date(timeIntervalSince1970: 1_700_000_000)
        projects[pIndex].codebases[cIndex].indexedFingerprint = fingerprint
        loadArtifact(for: fixture.codebaseID)
    }
}
