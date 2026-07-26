import Foundation
import Testing
@testable import AcaiGit

@Suite("GitWorktree", .serialized)
struct GitWorktreeTests {
    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Clones the fixture into a shared-store-shaped layout and returns (repository, commits).
    private func makeSharedClone(root: URL) async throws -> (GitRepository, GitFixture.Commits) {
        let source = root.appendingPathComponent("source", isDirectory: true)
        let commits = try GitFixture(directory: source).make()

        let store = root.appendingPathComponent("store", isDirectory: true)
        let repository = GitRepository(remoteURL: source, storeDirectory: store)
        try await repository.sync(ref: "main")
        return (repository, commits)
    }

    @Test("Two worktrees of one shared clone can sit at different commits simultaneously")
    func twoWorktreesAtDifferentCommits() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let (repository, _) = try await makeSharedClone(root: root)
        let worktree = GitWorktree(repositoryDirectory: repository.localPath)

        let mainCheckout = root.appendingPathComponent("checkout-main", isDirectory: true)
        try worktree.add(name: "checkout-main", at: mainCheckout)
        try GitCheckout(directory: mainCheckout).switchToDetached(ref: "main")

        let featureCheckout = root.appendingPathComponent("checkout-feature", isDirectory: true)
        try worktree.add(name: "checkout-feature", at: featureCheckout)
        try GitCheckout(directory: featureCheckout).switchToDetached(ref: "feature")

        // "main" worktree: has the file from the tagged commit, not the feature-branch-only file.
        #expect(FileManager.default.fileExists(atPath: mainCheckout.appendingPathComponent("Sub/Nested.swift").path))
        #expect(!FileManager.default.fileExists(atPath: mainCheckout.appendingPathComponent("Feature.swift").path))

        // "feature" worktree: has both, simultaneously, from the very same shared clone.
        #expect(FileManager.default.fileExists(
            atPath: featureCheckout.appendingPathComponent("Sub/Nested.swift").path))
        #expect(FileManager.default.fileExists(atPath: featureCheckout.appendingPathComponent("Feature.swift").path))

        // The shared clone's own working directory is untouched by either worktree's checkout.
        #expect(FileManager.default.fileExists(
            atPath: repository.localPath.appendingPathComponent("Sub/Nested.swift").path))
        #expect(!FileManager.default.fileExists(
            atPath: repository.localPath.appendingPathComponent("Feature.swift").path))
    }

    @Test("list() reports every registered worktree by name")
    func listsRegisteredWorktrees() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let (repository, _) = try await makeSharedClone(root: root)
        let worktree = GitWorktree(repositoryDirectory: repository.localPath)

        try worktree.add(name: "one", at: root.appendingPathComponent("one", isDirectory: true))
        try worktree.add(name: "two", at: root.appendingPathComponent("two", isDirectory: true))

        let names = try worktree.list()
        #expect(Set(names) == ["one", "two"])
    }

    @Test("remove() deregisters a worktree and deletes its working directory")
    func removeDeletesWorktree() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let (repository, _) = try await makeSharedClone(root: root)
        let worktree = GitWorktree(repositoryDirectory: repository.localPath)

        let checkout = root.appendingPathComponent("checkout", isDirectory: true)
        try worktree.add(name: "checkout", at: checkout)
        #expect(FileManager.default.fileExists(atPath: checkout.path))

        try worktree.remove(name: "checkout")

        #expect(try worktree.list().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: checkout.path))
    }

    @Test("remove() of an unregistered name is a no-op, not an error")
    func removeUnknownNameIsNoOp() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let (repository, _) = try await makeSharedClone(root: root)
        let worktree = GitWorktree(repositoryDirectory: repository.localPath)

        try worktree.remove(name: "never-existed")
    }
}
