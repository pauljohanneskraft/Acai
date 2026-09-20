#if os(macOS)
import AcaiGit
import Foundation
import Testing
@testable import AcaiApp

/// Real libgit2 against a local repository: a remote on no particular host, reached with no
/// account, which is exactly what #179 promises works for every git remote.
@Suite("ProjectCodebaseEditor remote sync")
@MainActor
struct ProjectCodebaseEditorRemoteSyncTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-remote-sync-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeEditor(store: ProjectStore, remoteService: GitRemoteService = LiveGitRemoteService())
        -> ProjectCodebaseEditor {
        ProjectCodebaseEditor(
            store: store, persist: {}, notify: {}, invalidateAnalysis: { _ in }, remoteService: remoteService)
    }

    @Test func addingAGenericRemoteClonesItWithoutAnAccount() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = try GitTestRepository.make(in: root)
        let store = ProjectStore(baseDir: root.appendingPathComponent("store"))
        let editor = makeEditor(store: store)
        let projectID = editor.addProject(title: "Demo", subtitle: "")

        await editor.addRemoteCodebase(
            to: projectID, name: "widgets", remoteURL: remote.directory, ref: "main", refKind: .branch)

        let codebase = try #require(store.projects.first?.codebases.first)
        #expect(codebase.managedCheckout?.refKind == .branch)
        #expect(codebase.managedCheckout?.lastSyncedCommitSHA == (try remote.git("rev-parse", "main")))
        #expect(codebase.repository?.remoteURL == remote.directory)
        #expect(codebase.repository?.ref == "main")
        #expect(codebase.repository?.host == .generic)
        #expect(FileManager.default.fileExists(atPath: codebase.directoryPath + "/README.md"))
    }

    @Test func switchingRefMovesTheWorktreeAndRecordsTheNewRef() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = try GitTestRepository.make(in: root)
        let store = ProjectStore(baseDir: root.appendingPathComponent("store"))
        let editor = makeEditor(store: store)
        let projectID = editor.addProject(title: "Demo", subtitle: "")
        await editor.addRemoteCodebase(
            to: projectID, name: "widgets", remoteURL: remote.directory, ref: "main", refKind: .branch)
        let codebaseID = try #require(store.projects.first?.codebases.first?.id)

        await editor.switchRef(codebaseID: codebaseID, ref: "feature", kind: .branch)

        let codebase = try #require(store.projects.first?.codebases.first)
        #expect(codebase.repository?.ref == "feature")
        #expect(codebase.managedCheckout?.lastSyncedCommitSHA == (try remote.git("rev-parse", "feature")))
        #expect(FileManager.default.fileExists(atPath: codebase.directoryPath + "/Feature.swift"))
    }

    @Test func pullPicksUpNewCommitsOnTheRemote() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = try GitTestRepository.make(in: root)
        let store = ProjectStore(baseDir: root.appendingPathComponent("store"))
        let editor = makeEditor(store: store)
        let projectID = editor.addProject(title: "Demo", subtitle: "")
        await editor.addRemoteCodebase(
            to: projectID, name: "widgets", remoteURL: remote.directory, ref: "main", refKind: .branch)
        let codebaseID = try #require(store.projects.first?.codebases.first?.id)

        try remote.commit("Later.swift", "struct Later {}", message: "later")
        await editor.pull(codebaseID: codebaseID)

        let codebase = try #require(store.projects.first?.codebases.first)
        #expect(codebase.managedCheckout?.lastSyncedCommitSHA == (try remote.git("rev-parse", "main")))
        #expect(FileManager.default.fileExists(atPath: codebase.directoryPath + "/Later.swift"))
    }

    @Test func aFailedSwitchLeavesTheCodebaseOnItsPreviousRef() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = try GitTestRepository.make(in: root)
        let store = ProjectStore(baseDir: root.appendingPathComponent("store"))
        let editor = makeEditor(store: store)
        let projectID = editor.addProject(title: "Demo", subtitle: "")
        await editor.addRemoteCodebase(
            to: projectID, name: "widgets", remoteURL: remote.directory, ref: "main", refKind: .branch)
        let before = try #require(store.projects.first?.codebases.first)

        await editor.switchRef(codebaseID: before.id, ref: "does-not-exist", kind: .branch)

        let after = try #require(store.projects.first?.codebases.first)
        #expect(after.repository?.ref == "main")
        #expect(after.managedCheckout == before.managedCheckout)
    }
}
#endif
