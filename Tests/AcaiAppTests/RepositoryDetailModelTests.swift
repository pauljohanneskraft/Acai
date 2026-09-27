import AcaiTestSupport
import Foundation
import Testing
@testable import AcaiApp

@Suite("RepositoryDetailModel", .timeLimit(.minutes(1)))
@MainActor
struct RepositoryDetailModelTests {
    private let remoteURL = URL(string: "https://example.com/octocat/widgets.git")!

    private func makeStore() throws -> ProjectStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-repository-detail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return ProjectStore(baseDir: root)
    }

    private func managedCodebase(named name: String) -> Codebase {
        Codebase(
            name: name, directoryPath: "/tmp/\(name)", managedCheckout: ManagedCheckout(),
            repository: CodebaseRepositoryReference(remoteURL: remoteURL, ref: "main"))
    }

    @Test func loadsSizeLastFetchedAndWorktreesOfASyncedHub() async throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.baseDir) }
        let service = FakeGitRemoteService()
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        service.inspections.value[remoteURL] = CloneInspection(
            isCloned: true, isShallow: true, lastFetchedAt: fetchedAt, worktreeNames: ["codebase-a", "codebase-b"])
        service.sizes.value[remoteURL] = 4096
        let details = RepositoryDetailModel(remoteURL: remoteURL, store: store, remoteService: service)
        #expect(details.onDiskSize == nil)
        #expect(details.worktreeNames.isEmpty)

        await details.loadDetails()

        #expect(details.onDiskSize == 4096)
        #expect(details.lastFetchedAt == fetchedAt)
        #expect(details.worktreeNames == ["codebase-a", "codebase-b"])
        #expect(details.isShallow)
        #expect(!details.isLoadingDetails)
    }

    @Test func fetchNowRefreshesTheDetailsAndSurfacesAFailure() async throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.baseDir) }
        let service = FakeGitRemoteService()
        service.inspections.value[remoteURL] = CloneInspection(
            isCloned: true, isShallow: false, lastFetchedAt: nil, worktreeNames: [])
        let details = RepositoryDetailModel(remoteURL: remoteURL, store: store, remoteService: service)

        await details.fetchNow()
        #expect(service.callCount(of: "fetch ") == 1)
        #expect(details.lastFetchedAt != nil)
        #expect(details.errorMessage == nil)

        service.failure.value = FakeGitRemoteService.UnknownRemote()
        await details.fetchNow()
        #expect(details.errorMessage != nil)
        #expect(!details.isFetching)
    }

    @Test func referencingCodebasesFollowTheStoreAfterRemoval() async throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.baseDir) }
        let first = managedCodebase(named: "a")
        let second = managedCodebase(named: "b")
        store.projects = [Project(title: "Demo", subtitle: "", codebases: [first, second])]
        let service = FakeGitRemoteService()
        service.inspections.value[remoteURL] = CloneInspection(
            isCloned: true, isShallow: false, lastFetchedAt: nil, worktreeNames: ["codebase-a", "codebase-b"])
        let details = RepositoryDetailModel(remoteURL: remoteURL, store: store, remoteService: service)
        await details.loadDetails()
        #expect(details.referencingCodebases.map(\.name) == ["a", "b"])
        #expect(details.worktreeNames.count == 2)

        service.inspections.value[remoteURL]?.worktreeNames = ["codebase-b"]
        let editor = ProjectCodebaseEditor(
            store: store, persist: {}, notify: {}, invalidateAnalysis: { _ in }, remoteService: service)
        await editor.removeCodebase(first.id)

        #expect(details.referencingCodebases.map(\.name) == ["b"])
        try await Eventually().waitUntil("the worktree list follows the removal") {
            details.worktreeNames == ["codebase-b"]
        }
    }
}
