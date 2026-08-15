import Foundation
import Testing
@testable import AcaiGit

@Suite("GitCheckout.mergeBase", .serialized)
struct GitCheckoutMergeBaseTests {
    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Resolves to the commit main and feature both descend from")
    func resolvesTheCommonAncestorOfMainAndFeature() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root.appendingPathComponent("repo", isDirectory: true)
        let commits = try GitFixture(directory: directory).make()

        let mergeBase = try GitCheckout(directory: directory).mergeBase("main", "feature")
        #expect(mergeBase == commits.tagged)
    }

    @Test("Is symmetric in its two arguments")
    func isSymmetric() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root.appendingPathComponent("repo", isDirectory: true)
        try GitFixture(directory: directory).make()

        let checkout = try GitCheckout(directory: directory)
        #expect(try checkout.mergeBase("main", "feature") == checkout.mergeBase("feature", "main"))
    }

    @Test("An unresolvable revision throws rather than crashing")
    func unresolvableRevisionThrows() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root.appendingPathComponent("repo", isDirectory: true)
        try GitFixture(directory: directory).make()

        #expect(throws: (any Error).self) {
            _ = try GitCheckout(directory: directory).mergeBase("main", "does-not-exist")
        }
    }

    @Test("Resolves correctly from a linked worktree checkout, not just the shared clone's own directory")
    func resolvesFromAWorktreeCheckout() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        let commits = try GitFixture(directory: source).make()

        let store = root.appendingPathComponent("store", isDirectory: true)
        let repository = GitRepository(remoteURL: source, storeDirectory: store)
        try await repository.sync(ref: "main")

        let worktree = GitWorktree(repositoryDirectory: repository.localPath)
        let checkoutDirectory = root.appendingPathComponent("checkout-feature", isDirectory: true)
        try worktree.add(name: "checkout-feature", at: checkoutDirectory)
        try GitCheckout(directory: checkoutDirectory).switchToDetached(ref: "feature")

        let mergeBase = try GitCheckout(directory: checkoutDirectory).mergeBase("main", "feature")
        #expect(mergeBase == commits.tagged)
    }
}
