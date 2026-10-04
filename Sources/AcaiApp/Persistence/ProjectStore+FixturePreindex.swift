import Foundation
import AcaiCore

extension ProjectStore {
    struct FixturePreindex: Sendable {
        let codebaseID: UUID
        let projectID: UUID
        let sourcePath: String
        let artifact: CodeArtifact
    }

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
              let cIndex = projects[pIndex].codebases.firstIndex(where: { $0.id == fixture.codebaseID })
        else { return }
        projects[pIndex].codebases[cIndex].hasArtifact = true
        // Fixed so the date on screen is the same in every screenshot run.
        projects[pIndex].codebases[cIndex].lastIndexed = Date(timeIntervalSince1970: 1_700_000_000)
        projects[pIndex].codebases[cIndex].indexedFingerprint = fingerprint
        loadArtifact(for: fixture.codebaseID)
    }
}
