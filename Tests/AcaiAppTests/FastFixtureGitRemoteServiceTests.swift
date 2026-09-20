import AcaiGit
import Foundation
import Testing
@testable import AcaiApp

@Suite("FastFixtureGitRemoteService")
struct FastFixtureGitRemoteServiceTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeService(root: URL, refs: [String: [String: String]]) throws -> FastFixtureGitRemoteService {
        var sourceDirectoriesByRef: [String: URL] = [:]
        for (ref, files) in refs {
            let refDirectory = root.appendingPathComponent(ref, isDirectory: true)
            try FileManager.default.createDirectory(at: refDirectory, withIntermediateDirectories: true)
            for (relativePath, content) in files {
                try content.write(
                    to: refDirectory.appendingPathComponent(relativePath), atomically: true, encoding: .utf8)
            }
            sourceDirectoriesByRef[ref] = refDirectory
        }
        return FastFixtureGitRemoteService(sourceDirectoriesByRef: sourceDirectoriesByRef)
    }

    private let endpoint = RemoteEndpoint(
        remoteURL: URL(string: "https://example.com/octocat/widgets.git")!, gitHubCredential: nil)

    private func target(_ ref: String) -> RemoteCheckoutTarget {
        RemoteCheckoutTarget(endpoint: endpoint, ref: ref)
    }

    private func makeDestination(root: URL) -> GitWorktreeDestination {
        GitWorktreeDestination(
            hubStoreDirectory: root.appendingPathComponent("hub"), worktreeName: "codebase-1",
            worktreeDirectory: root.appendingPathComponent("worktree", isDirectory: true), locks: GitRepositoryLocks())
    }

    @Test("resyncWorktree copies the staged ref's content and returns a deterministic SHA, instantly")
    func resyncCopiesStagedContent() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try makeService(root: root, refs: ["main": ["Widget.swift": "class Widget {}"]])
        let destination = makeDestination(root: root)

        let sha = try await service.resyncWorktree(target("main"), destination: destination)

        let widget = destination.worktreeDirectory.appendingPathComponent("Widget.swift")
        #expect(FileManager.default.fileExists(atPath: widget.path))
        #expect(sha.count == 64) // SHA-256 hex digest, not a real git SHA
        let secondSHA = try await service.resyncWorktree(target("main"), destination: destination)
        #expect(sha == secondSHA)
    }

    @Test("resyncWorktree replaces a pre-existing worktree rather than merging into it")
    func resyncReplacesExistingWorktree() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try makeService(root: root, refs: ["main": ["New.swift": "class New {}"]])
        let destination = makeDestination(root: root)
        let worktree = destination.worktreeDirectory

        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "stale".write(to: worktree.appendingPathComponent("Stale.swift"), atomically: true, encoding: .utf8)

        _ = try await service.resyncWorktree(target("main"), destination: destination)

        #expect(!FileManager.default.fileExists(atPath: worktree.appendingPathComponent("Stale.swift").path))
        #expect(FileManager.default.fileExists(atPath: worktree.appendingPathComponent("New.swift").path))
    }

    @Test("attachWorktree and resyncWorktree both copy the staged ref into the worktree directory")
    func attachAndResyncCopyIntoWorktree() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try makeService(
            root: root, refs: [
                "main": ["Widget.swift": "class Widget {}"],
                "feature": ["Widget.swift": "class Widget {}", "Extra.swift": "class Extra {}"]
            ])

        let destination = makeDestination(root: root)
        let worktree = destination.worktreeDirectory

        let (attachSHA, remoteURL) = try await service.attachWorktree(target("main"), destination: destination)
        #expect(FileManager.default.fileExists(atPath: worktree.appendingPathComponent("Widget.swift").path))
        #expect(!FileManager.default.fileExists(atPath: worktree.appendingPathComponent("Extra.swift").path))
        #expect(remoteURL == endpoint.remoteURL)

        let resyncSHA = try await service.resyncWorktree(target("feature"), destination: destination)
        #expect(FileManager.default.fileExists(atPath: worktree.appendingPathComponent("Extra.swift").path))
        #expect(attachSHA != resyncSHA)
    }

    @Test("Listing reports exactly the staged refs, and attachWorktree throws for an unstaged ref")
    func listingReflectsStagedContentOnly() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try makeService(
            root: root, refs: ["main": ["A.swift": "class A {}"], "release": ["A.swift": "class A {}"]])

        let listing = try await service.listRemote(endpoint)
        #expect(Set(listing.refs.map(\.name)) == ["main", "release"])

        await #expect(throws: (any Error).self) {
            try await service.attachWorktree(target("does-not-exist"), destination: makeDestination(root: root))
        }
    }
}
