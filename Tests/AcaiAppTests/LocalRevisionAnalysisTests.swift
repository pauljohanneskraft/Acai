#if os(macOS)
import AcaiGit
import Foundation
import Testing
@testable import AcaiApp

/// #181: a local folder analysed at another revision, with the user's checkout left exactly as it was.
@Suite("Local folder at another revision")
@MainActor
struct LocalRevisionAnalysisTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-local-revision-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Every file under `directory` (including `.git`) with its bytes and modification date.
    private func snapshot(of directory: URL) throws -> [String: (Data, Date)] {
        var result: [String: (Data, Date)] = [:]
        let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey])
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { continue }
            result[url.path] = (try Data(contentsOf: url), values.contentModificationDate ?? .distantPast)
        }
        return result
    }

    /// Main checked out, with a modified tracked file, a staged new file and an untracked file.
    private func makeDirtyCheckout(in root: URL) throws -> GitTestRepository {
        let repository = try GitTestRepository.make(in: root, named: "checkout")
        try "edited, not committed".write(
            to: repository.directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "struct Staged {}".write(
            to: repository.directory.appendingPathComponent("Staged.swift"), atomically: true, encoding: .utf8)
        try repository.git("add", "Staged.swift")
        try "struct Untracked {}".write(
            to: repository.directory.appendingPathComponent("Untracked.swift"), atomically: true, encoding: .utf8)
        return repository
    }

    @Test func analysingAnotherRevisionLeavesTheCheckoutExactlyAsItWas() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try makeDirtyCheckout(in: root)
        let statusBefore = try repository.git("status", "--porcelain")
        let headBefore = try repository.git("rev-parse", "HEAD")
        let branchBefore = try repository.git("rev-parse", "--abbrev-ref", "HEAD")
        let filesBefore = try snapshot(of: repository.directory)

        let store = ProjectStore(baseDir: root.appendingPathComponent("store"))
        let editor = ProjectCodebaseEditor(store: store, persist: {}, notify: {}, invalidateAnalysis: { _ in })
        let projectID = editor.addProject(title: "Demo", subtitle: "")
        editor.addCodebase(to: projectID, name: "checkout", directoryURL: repository.directory)
        let codebaseID = try #require(store.projects.first?.codebases.first?.id)

        await editor.setAnalysedRevision("feature", codebaseID: codebaseID)

        // Taken before any `git` command runs: those may refresh `.git/index` themselves.
        let filesAfter = try snapshot(of: repository.directory)
        let artifact = try #require(store.artifacts[codebaseID])
        #expect(artifact.types.contains { $0.name == "Feature" })
        #expect(!artifact.types.contains { $0.name == "Staged" })
        #expect(!artifact.types.contains { $0.name == "Untracked" })

        #expect(try repository.git("status", "--porcelain") == statusBefore)
        #expect(try repository.git("rev-parse", "HEAD") == headBefore)
        #expect(try repository.git("rev-parse", "--abbrev-ref", "HEAD") == branchBefore)
        #expect(Set(filesAfter.keys) == Set(filesBefore.keys))
        for (path, before) in filesBefore {
            #expect(filesAfter[path]?.0 == before.0, "\(path) changed")
            #expect(filesAfter[path]?.1 == before.1, "\(path) was touched")
        }
    }

    @Test func clearingThePinAnalysesTheWorkingTreeAgain() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try makeDirtyCheckout(in: root)
        let store = ProjectStore(baseDir: root.appendingPathComponent("store"))
        let editor = ProjectCodebaseEditor(store: store, persist: {}, notify: {}, invalidateAnalysis: { _ in })
        let projectID = editor.addProject(title: "Demo", subtitle: "")
        editor.addCodebase(to: projectID, name: "checkout", directoryURL: repository.directory)
        let codebaseID = try #require(store.projects.first?.codebases.first?.id)

        await editor.setAnalysedRevision("feature", codebaseID: codebaseID)
        await editor.setAnalysedRevision(nil, codebaseID: codebaseID)

        let artifact = try #require(store.artifacts[codebaseID])
        #expect(store.projects.first?.codebases.first?.analysedRevision == nil)
        #expect(artifact.types.contains { $0.name == "Untracked" })
        #expect(!artifact.types.contains { $0.name == "Feature" })
    }

    @Test func aPinnedRevisionStaysFreshWhileTheWorkingTreeChangesAndGoesStaleWhenTheRefMoves() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try makeDirtyCheckout(in: root)
        let checker = CodebaseFreshnessChecker(directoryPath: repository.directory.path, revision: "feature")

        let indexed = checker.currentFingerprint()
        #expect(indexed == .git(headCommitSHA: try repository.git("rev-parse", "feature"), isDirty: false))

        try "more edits".write(
            to: repository.directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        #expect(checker.currentFingerprint() == indexed)

        try repository.git("stash", "-u")
        try repository.git("checkout", "-q", "feature")
        try repository.commit("Later.swift", "struct Later {}", message: "later")
        #expect(checker.currentFingerprint() != indexed)
    }

    @Test func aDetectedOriginNeverKeepsItsCredentials() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try GitTestRepository.make(in: root, named: "checkout")
        try repository.git("remote", "add", "origin", "https://user:secret@example.test/owner/repo.git")

        let reference = LocalGitRepositoryDetector(directory: repository.directory).detect()

        #expect(reference?.remoteURL == URL(string: "https://example.test/owner/repo.git"))
    }
}
#endif
