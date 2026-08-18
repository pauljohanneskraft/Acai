import AcaiGit
import Foundation
import Testing
@testable import AcaiApp

@Suite("GitWorktreeSync (app-layer wiring)", .serialized)
struct GitWorktreeSyncTests {
    @Test("Two codebases attaching worktrees for the same remote share one hub clone")
    func sharesOneHubAcrossTwoWorktrees() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try makeFixtureRepository(at: source)

        let hubStoreDirectory = root.appendingPathComponent("hub-store", isDirectory: true)
        let locks = GitRepositoryLocks()

        let mainSync = GitWorktreeSync(
            transportURL: source, ref: "main", hubStoreDirectory: hubStoreDirectory, locks: locks)
        let featureSync = GitWorktreeSync(
            transportURL: source, ref: "feature", hubStoreDirectory: hubStoreDirectory, locks: locks)

        #expect(mainSync.hub.localPath == featureSync.hub.localPath)

        let mainWorktree = root.appendingPathComponent("worktree-main", isDirectory: true)
        try await mainSync.attachWorktree(named: "codebase-main", at: mainWorktree)

        let featureWorktree = root.appendingPathComponent("worktree-feature", isDirectory: true)
        try await featureSync.attachWorktree(named: "codebase-feature", at: featureWorktree)

        // One shared object store on disk, not two independent clones.
        let hubContents = try FileManager.default.contentsOfDirectory(
            at: hubStoreDirectory, includingPropertiesForKeys: nil)
        #expect(hubContents.count == 1)

        #expect(FileManager.default.fileExists(atPath: mainWorktree.appendingPathComponent("README.md").path))
        #expect(!FileManager.default.fileExists(atPath: mainWorktree.appendingPathComponent("Feature.swift").path))
        #expect(FileManager.default.fileExists(atPath: featureWorktree.appendingPathComponent("Feature.swift").path))
    }

    @Test("resyncWorktree moves an already-attached worktree to a new ref without re-registering it")
    func resyncMovesExistingWorktree() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try makeFixtureRepository(at: source)

        let hubStoreDirectory = root.appendingPathComponent("hub-store", isDirectory: true)
        let sync = GitWorktreeSync(
            transportURL: source, ref: "main", hubStoreDirectory: hubStoreDirectory, locks: GitRepositoryLocks())

        let worktree = root.appendingPathComponent("worktree", isDirectory: true)
        try await sync.attachWorktree(named: "codebase-1", at: worktree)
        #expect(!FileManager.default.fileExists(atPath: worktree.appendingPathComponent("Feature.swift").path))

        let movedSync = GitWorktreeSync(
            transportURL: source, ref: "feature", hubStoreDirectory: hubStoreDirectory, locks: GitRepositoryLocks())
        try await movedSync.resyncWorktree(at: worktree)

        #expect(FileManager.default.fileExists(atPath: worktree.appendingPathComponent("Feature.swift").path))
    }

    @Test("removeWorktree deletes the worktree but leaves the shared hub clone intact")
    func removeWorktreeLeavesHubIntact() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try makeFixtureRepository(at: source)

        let hubStoreDirectory = root.appendingPathComponent("hub-store", isDirectory: true)
        let sync = GitWorktreeSync(
            transportURL: source, ref: "main", hubStoreDirectory: hubStoreDirectory, locks: GitRepositoryLocks())

        let worktree = root.appendingPathComponent("worktree", isDirectory: true)
        try await sync.attachWorktree(named: "codebase-1", at: worktree)
        #expect(FileManager.default.fileExists(atPath: worktree.path))

        try await sync.removeWorktree(named: "codebase-1")

        #expect(!FileManager.default.fileExists(atPath: worktree.path))
        #expect(sync.hub.isCloned)
    }

    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitWorktreeSyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A small repo with `main` (one commit, `README.md`) and `feature` (one commit ahead, adds
    /// `Feature.swift`), mirroring `AcaiGitTests`' own `GitFixture` shape.
    private func makeFixtureRepository(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try git(["init", "-q", "--initial-branch=main"], in: directory)
        try git(["config", "user.email", "t@t.test"], in: directory)
        try git(["config", "user.name", "Test"], in: directory)
        try "hello".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try git(["add", "-A"], in: directory)
        try git(["commit", "-q", "-m", "initial"], in: directory)
        try git(["checkout", "-q", "-b", "feature"], in: directory)
        try "feature".write(to: directory.appendingPathComponent("Feature.swift"), atomically: true, encoding: .utf8)
        try git(["add", "-A"], in: directory)
        try git(["commit", "-q", "-m", "feature work"], in: directory)
        try git(["checkout", "-q", "main"], in: directory)
    }

    private func git(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
    }
}
