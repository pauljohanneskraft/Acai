#if os(macOS)
import AcaiGit
import AcaiTestSupport
import Foundation
import Testing
@testable import AcaiApp

/// Real libgit2 against a local repository: a remote on no particular host, reached with no
/// account, which is exactly what #179 promises works for every git remote.
@Suite("ProjectCodebaseEditor remote sync", .timeLimit(.minutes(1)))
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

    /// `FixtureGitRemoteService` rather than the live one: libgit2's local transport can't clone
    /// shallowly, and the fixture leaves exactly the on-disk state a real shallow clone does.
    @Test func aLatestSnapshotCloneIsShallowUntilFullHistoryIsFetched() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = try GitTestRepository.make(in: root)
        let store = ProjectStore(baseDir: root.appendingPathComponent("store"))
        let service = FixtureGitRemoteService(fixtureRemoteURL: nil)
        let editor = makeEditor(store: store, remoteService: service)
        let projectID = editor.addProject(title: "Demo", subtitle: "")
        let endpoint = RemoteEndpoint(remoteURL: remote.directory, gitHubCredential: nil)
        let absent = await service.inspectClone(endpoint, hubStoreDirectory: store.gitRepositoriesDir)
        #expect(absent == .absent)

        await editor.addRemoteCodebase(
            to: projectID, name: "widgets", remoteURL: remote.directory, ref: "main", refKind: .branch,
            depth: .latestSnapshot)

        let codebaseID = try #require(store.projects.first?.codebases.first?.id)
        let shallow = await service.inspectClone(endpoint, hubStoreDirectory: store.gitRepositoriesDir)
        #expect(shallow.isCloned)
        #expect(shallow.isShallow)
        #expect(shallow.worktreeNames == [store.gitWorktreeName(for: codebaseID)])

        let fetched = await editor.fetchFullHistory(remoteURL: remote.directory)
        #expect(fetched)
        let deepened = await service.inspectClone(endpoint, hubStoreDirectory: store.gitRepositoriesDir)
        #expect(deepened.isCloned)
        #expect(!deepened.isShallow)
        let size = await service.onDiskSize(of: endpoint, hubStoreDirectory: store.gitRepositoriesDir)
        #expect((size ?? 0) > 0)
    }

    /// A clone that outlives its project: what it produced is discarded and reported, never filed
    /// under whichever project now sits where the deleted one did.
    @Test func aCloneFinishingAfterItsProjectIsDeletedIsDiscardedRatherThanMisfiled() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = try GitTestRepository.make(in: root)
        let store = ProjectStore(baseDir: root.appendingPathComponent("store"))
        let service = GatedCloneRemoteService()
        let editor = makeEditor(store: store, remoteService: service)
        let doomedProjectID = editor.addProject(title: "Doomed", subtitle: "")
        let survivingProjectID = editor.addProject(title: "Surviving", subtitle: "")

        let clone = Task {
            await editor.addRemoteCodebase(
                to: doomedProjectID, name: "widgets", remoteURL: remote.directory, ref: "main",
                refKind: .branch)
        }
        // Deleted in exactly the window the clone suspends in, with the worktree already on disk.
        try await service.attached.wait(timeout: .seconds(30))
        editor.removeProject(doomedProjectID)
        await service.mayFinish.open()
        await clone.value

        #expect(store.projects.map(\.id) == [survivingProjectID])
        #expect(store.projects.allSatisfy(\.codebases.isEmpty))
        // Told, not silently dropped.
        #expect(store.lastError != nil)
        // The orphaned worktree, and the hub clone left holding nothing, are both gone.
        #expect(directoryNames(in: store.gitWorktreesDir).isEmpty)
        #expect(directoryNames(in: store.gitRepositoriesDir).isEmpty)
    }

    private func directoryNames(in directory: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }
    }
}

/// `LiveGitRemoteService`, but the clone parks once the worktree is on disk so a test can mutate
/// the project list in the window `addRemoteCodebase` suspends in.
private struct GatedCloneRemoteService: GitRemoteService {
    let attached = AsyncGate()
    let mayFinish = AsyncGate()
    private let live = LiveGitRemoteService()

    func listRemote(_ endpoint: RemoteEndpoint) async throws -> GitRemoteListing.Result {
        try await live.listRemote(endpoint)
    }

    @discardableResult
    func attachWorktree(
        _ target: RemoteCheckoutTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> (headSHA: String, remoteURL: URL) {
        let result = try await live.attachWorktree(target, destination: destination, onProgress: onProgress)
        await attached.open()
        await mayFinish.wait()
        return result
    }

    @discardableResult
    func resyncWorktree(
        _ target: RemoteCheckoutTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> String {
        try await live.resyncWorktree(target, destination: destination, onProgress: onProgress)
    }

    func refs(of endpoint: RemoteEndpoint, hubStoreDirectory: URL) async throws -> [GitCheckout.Ref] {
        try await live.refs(of: endpoint, hubStoreDirectory: hubStoreDirectory)
    }

    func fetchFullHistory(
        _ endpoint: RemoteEndpoint, hubStoreDirectory: URL, locks: GitRepositoryLocks,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws {
        try await live.fetchFullHistory(
            endpoint, hubStoreDirectory: hubStoreDirectory, locks: locks, onProgress: onProgress)
    }

    func fetch(
        _ endpoint: RemoteEndpoint, hubStoreDirectory: URL, locks: GitRepositoryLocks,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws {
        try await live.fetch(endpoint, hubStoreDirectory: hubStoreDirectory, locks: locks, onProgress: onProgress)
    }

    func inspectClone(_ endpoint: RemoteEndpoint, hubStoreDirectory: URL) async -> CloneInspection {
        await live.inspectClone(endpoint, hubStoreDirectory: hubStoreDirectory)
    }

    func onDiskSize(of endpoint: RemoteEndpoint, hubStoreDirectory: URL) async -> Int64? {
        await live.onDiskSize(of: endpoint, hubStoreDirectory: hubStoreDirectory)
    }
}
#endif
