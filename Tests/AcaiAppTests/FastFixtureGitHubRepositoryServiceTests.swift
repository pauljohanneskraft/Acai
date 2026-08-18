import AcaiGit
import Foundation
import Testing
@testable import AcaiApp

@Suite("FastFixtureGitHubRepositoryService")
struct FastFixtureGitHubRepositoryServiceTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeService(root: URL, refs: [String: [String: String]]) throws -> FastFixtureGitHubRepositoryService {
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
        return FastFixtureGitHubRepositoryService(sourceDirectoriesByRef: sourceDirectoriesByRef)
    }

    private let target = GitHubRepositoryTarget(
        credential: .personalAccessToken("fixture-token"), owner: "octocat", repo: "widgets", ref: "main")

    @Test("sync copies the staged ref's content and returns a deterministic SHA, instantly")
    func syncCopiesStagedContent() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try makeService(root: root, refs: ["main": ["Widget.swift": "class Widget {}"]])

        let destination = root.appendingPathComponent("destination", isDirectory: true)
        let sha = try await service.sync(target, into: destination)

        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Widget.swift").path))
        #expect(sha.count == 64) // SHA-256 hex digest, not a real git SHA
        let secondSHA = try await service.sync(target, into: destination)
        #expect(sha == secondSHA) // deterministic, not derived from timing/randomness
    }

    @Test("sync replaces a pre-existing destination rather than merging into it")
    func syncReplacesExistingDestination() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try makeService(root: root, refs: ["main": ["New.swift": "class New {}"]])

        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "stale".write(
            to: destination.appendingPathComponent("Stale.swift"), atomically: true, encoding: .utf8)

        _ = try await service.sync(target, into: destination)

        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Stale.swift").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("New.swift").path))
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

        let worktree = root.appendingPathComponent("worktree", isDirectory: true)
        let destination = GitWorktreeDestination(
            hubStoreDirectory: root.appendingPathComponent("hub"), worktreeName: "codebase-1",
            worktreeDirectory: worktree, locks: GitRepositoryLocks())

        let (attachSHA, remoteURL) = try await service.attachWorktree(target, destination: destination)
        #expect(FileManager.default.fileExists(atPath: worktree.appendingPathComponent("Widget.swift").path))
        #expect(!FileManager.default.fileExists(atPath: worktree.appendingPathComponent("Extra.swift").path))
        #expect(remoteURL.absoluteString.contains("octocat/widgets"))

        let featureTarget = GitHubRepositoryTarget(
            credential: target.credential, owner: target.owner, repo: target.repo, ref: "feature")
        let resyncSHA = try await service.resyncWorktree(featureTarget, destination: destination)
        #expect(FileManager.default.fileExists(atPath: worktree.appendingPathComponent("Extra.swift").path))
        #expect(attachSHA != resyncSHA) // different refs canonically resolve to different SHAs
    }

    @Test("refs lists exactly the staged ref names, and sync throws for an unstaged ref")
    func refsReflectsStagedContentOnly() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try makeService(
            root: root, refs: ["main": ["A.swift": "class A {}"], "release": ["A.swift": "class A {}"]])

        let refs = try await service.refs(credential: target.credential, owner: "octocat", repo: "widgets")
        #expect(Set(refs.map(\.name)) == ["main", "release"])

        let unstagedTarget = GitHubRepositoryTarget(
            credential: target.credential, owner: target.owner, repo: target.repo, ref: "does-not-exist")
        await #expect(throws: (any Error).self) {
            try await service.sync(unstagedTarget, into: root.appendingPathComponent("out"))
        }
    }
}
