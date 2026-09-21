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

    @Test func twoCodebasesOfOneRemoteShareACloneAndDeletingTheLastRemovesIt() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = try GitTestRepository.make(in: root)
        let store = ProjectStore(baseDir: root.appendingPathComponent("store"))
        let editor = makeEditor(store: store)
        let projectID = editor.addProject(title: "Demo", subtitle: "")

        await editor.addRemoteCodebase(
            to: projectID, name: "main", remoteURL: remote.directory, ref: "main", refKind: .branch)
        await editor.addRemoteCodebase(
            to: projectID, name: "feature", remoteURL: remote.directory, ref: "feature", refKind: .branch)

        let codebases = try #require(store.projects.first?.codebases)
        #expect(codebases.count == 2)
        #expect(directoryNames(in: store.gitRepositoriesDir).count == 1)
        #expect(directoryNames(in: store.gitWorktreesDir).count == 2)
        let mainCodebase = try #require(codebases.first { $0.name == "main" })
        let featureCodebase = try #require(codebases.first { $0.name == "feature" })
        #expect(!FileManager.default.fileExists(atPath: mainCodebase.directoryPath + "/Feature.swift"))
        #expect(FileManager.default.fileExists(atPath: featureCodebase.directoryPath + "/Feature.swift"))

        await editor.removeCodebase(mainCodebase.id)
        #expect(directoryNames(in: store.gitRepositoriesDir).count == 1)
        #expect(directoryNames(in: store.gitWorktreesDir).count == 1)

        await editor.removeCodebase(featureCodebase.id)
        #expect(directoryNames(in: store.gitRepositoriesDir).isEmpty)
        #expect(directoryNames(in: store.gitWorktreesDir).isEmpty)
        #expect(RepositoryIndex(projects: store.projects).entries().isEmpty)
    }

    private func directoryNames(in directory: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }
    }
}
#endif
