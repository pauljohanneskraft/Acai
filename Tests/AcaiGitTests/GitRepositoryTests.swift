import Foundation
import Testing
@testable import AcaiGit

@Suite("GitRepository", .serialized)
struct GitRepositoryTests {
    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Two GitRepositorys for the same remote resolve to the same shared clone")
    func dedupsByRemoteURL() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()

        let store = root.appendingPathComponent("store", isDirectory: true)
        let first = GitRepository(remoteURL: source, storeDirectory: store)
        let second = GitRepository(remoteURL: source, storeDirectory: store)

        #expect(first.localPath == second.localPath)

        try await first.sync(ref: "main")
        // Reusing the same shared clone: the second `GitRepository` value sees what the first
        // already synced without cloning again (a second full clone would fail anyway, since
        // `GitClone` would try to move a scratch clone on top of a non-empty destination it didn't
        // create — this only succeeds if `sync` here goes through the existing-repo fetch path).
        try await second.fetch()

        #expect(FileManager.default.fileExists(atPath: first.localPath.appendingPathComponent("README.md").path))
    }

    @Test("Different remotes under the same store resolve to different local paths")
    func distinctRemotesDontCollide() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = root.appendingPathComponent("store", isDirectory: true)
        let first = GitRepository(remoteURL: URL(fileURLWithPath: "/a/repo"), storeDirectory: store)
        let second = GitRepository(remoteURL: URL(fileURLWithPath: "/b/repo"), storeDirectory: store)

        #expect(first.localPath != second.localPath)
    }

    @Test("Credentials embedded in the remote URL don't change the store path or leak into it")
    func credentialsDontAffectStoreKey() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = root.appendingPathComponent("store", isDirectory: true)
        let plain = GitRepository(remoteURL: URL(string: "https://github.com/owner/repo.git")!, storeDirectory: store)
        var authenticated = URLComponents(string: "https://github.com/owner/repo.git")!
        authenticated.user = "x-access-token"
        authenticated.password = "super-secret-token"
        let withCredentials = GitRepository(remoteURL: authenticated.url!, storeDirectory: store)

        #expect(plain.localPath == withCredentials.localPath)
        #expect(!withCredentials.localPath.path.contains("super-secret-token"))
    }

    @Test("refs() lists branches and tags off the shared clone")
    func refsListsBranchesAndTags() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()

        let store = root.appendingPathComponent("store", isDirectory: true)
        let repository = GitRepository(remoteURL: source, storeDirectory: store)
        try await repository.sync(ref: "main")

        let names = try repository.refs().map(\.name)
        #expect(names.contains("main"))
        #expect(names.contains("feature"))
        #expect(names.contains("v1"))
    }

    @Test("resolve(subpath:ref:) extracts a prior revision without touching the shared clone")
    func resolveExtractsPriorRevision() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()

        let store = root.appendingPathComponent("store", isDirectory: true)
        let repository = GitRepository(remoteURL: source, storeDirectory: store)
        try await repository.sync(ref: "main")

        let extracted = try repository.resolve(subpath: nil, ref: "HEAD~1")
        defer { try? FileManager.default.removeItem(at: extracted) }

        #expect(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("README.md").path))
        #expect(!FileManager.default.fileExists(atPath: extracted.appendingPathComponent("Sub/Nested.swift").path))
        // The shared clone's own working directory (at HEAD, the tagged commit) is untouched.
        #expect(FileManager.default.fileExists(
            atPath: repository.localPath.appendingPathComponent("Sub/Nested.swift").path))
    }

    @Test("commitHistory walks first-parent history most-recent-first")
    func commitHistoryWalksParents() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        let commits = try GitFixture(directory: source).make()

        let store = root.appendingPathComponent("store", isDirectory: true)
        let repository = GitRepository(remoteURL: source, storeDirectory: store)
        try await repository.sync(ref: "main")

        let history = try repository.commitHistory(ref: "main", limit: 10)

        #expect(history.map(\.sha) == [commits.tagged, commits.initial])
        #expect(history.first?.summary == "add nested file")
    }

    @Test("commitHistory respects the limit parameter")
    func commitHistoryRespectsLimit() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()

        let store = root.appendingPathComponent("store", isDirectory: true)
        let repository = GitRepository(remoteURL: source, storeDirectory: store)
        try await repository.sync(ref: "main")

        let history = try repository.commitHistory(ref: "main", limit: 1)
        #expect(history.count == 1)
    }

    @Test("isCloned/onDiskSize/lastFetchedAt reflect an uncloned repository")
    func metadataBeforeCloning() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = root.appendingPathComponent("store", isDirectory: true)
        let repository = GitRepository(remoteURL: URL(fileURLWithPath: "/never/cloned"), storeDirectory: store)

        #expect(!repository.isCloned)
        #expect(repository.onDiskSize == nil)
        #expect(repository.lastFetchedAt == nil)
    }

    @Test("isCloned/onDiskSize/lastFetchedAt reflect a synced repository")
    func metadataAfterCloning() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()

        let store = root.appendingPathComponent("store", isDirectory: true)
        let repository = GitRepository(remoteURL: source, storeDirectory: store)
        try await repository.sync(ref: "main")

        #expect(repository.isCloned)
        #expect((repository.onDiskSize ?? 0) > 0)
        #expect(repository.lastFetchedAt != nil)
    }
}
