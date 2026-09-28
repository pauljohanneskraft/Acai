import AcaiGit
import Foundation
import Testing
@testable import AcaiApp

@Suite("Project Store git storage", .timeLimit(.minutes(1)))
@MainActor
struct ProjectStoreGitStorageTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-git-storage-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private let remoteURL = URL(string: "https://github.com/octocat/widgets.git")!

    @Test func sweepDeletesOnlyUnreferencedClonesAndWorktrees() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(baseDir: dir)

        var codebase = Codebase(name: "widgets", directoryPath: "")
        codebase.managedCheckout = ManagedCheckout()
        codebase.repository = CodebaseRepositoryReference(remoteURL: remoteURL, ref: "main")
        var project = Project(title: "Demo", subtitle: "")
        project.codebases = [codebase]
        store.projects = [project]

        let fileManager = FileManager.default
        let referencedClone = GitRepository(remoteURL: remoteURL, storeDirectory: store.gitRepositoriesDir).localPath
        let unreferencedClone = store.gitRepositoriesDir.appendingPathComponent("unreferenced", isDirectory: true)
        let liveWorktree = store.gitWorktreeURL(for: codebase.id)
        let orphanedWorktree = store.gitWorktreeURL(for: UUID())
        for directory in [referencedClone, unreferencedClone, liveWorktree, orphanedWorktree] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        await GitStorageSweep(store: store).run()

        #expect(fileManager.fileExists(atPath: referencedClone.path))
        #expect(fileManager.fileExists(atPath: liveWorktree.path))
        #expect(!fileManager.fileExists(atPath: unreferencedClone.path))
        #expect(!fileManager.fileExists(atPath: orphanedWorktree.path))
    }

    @Test func sweepIsEmptyWhenEverythingIsReferenced() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(baseDir: dir)

        #expect(GitStorageSweep(store: store).isEmpty)
    }
}
