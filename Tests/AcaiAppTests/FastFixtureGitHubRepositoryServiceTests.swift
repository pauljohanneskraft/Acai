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

        let sha = try await service.resyncWorktree(target, destination: destination)

        let widget = destination.worktreeDirectory.appendingPathComponent("Widget.swift")
        #expect(FileManager.default.fileExists(atPath: widget.path))
        #expect(sha.count == 64) // SHA-256 hex digest, not a real git SHA
        let secondSHA = try await service.resyncWorktree(target, destination: destination)
        #expect(sha == secondSHA) // deterministic, not derived from timing/randomness
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

        _ = try await service.resyncWorktree(target, destination: destination)

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

    @Test("refs lists exactly the staged ref names, and attachWorktree throws for an unstaged ref")
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
            try await service.attachWorktree(unstagedTarget, destination: makeDestination(root: root))
        }
    }
}
