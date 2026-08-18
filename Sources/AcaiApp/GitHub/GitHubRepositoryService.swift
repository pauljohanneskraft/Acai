import Foundation
import AcaiGit
import CryptoKit

struct GitHubRepositoryTarget: Sendable {
    var credential: GitHubCredential
    var owner: String
    var repo: String
    var ref: String
}

struct GitWorktreeDestination: Sendable {
    /// One subdirectory per remote — see `ProjectStore.gitRepositoriesDir`.
    var hubStoreDirectory: URL
    /// Unused by `resyncWorktree`, which moves an already-registered worktree rather than
    /// creating one.
    var worktreeName: String
    var worktreeDirectory: URL
    /// Serializes fetch-vs-checkout against the shared hub clone across every codebase referencing
    /// it — see `ProjectStore.gitRepositoryLocks`.
    var locks: GitRepositoryLocks
}

/// The repository/branch/tag/clone operations `NewCodebaseSheet`, `CodebaseDetailView`, and
/// `ProjectCodebaseEditor` need against a GitHub-backed codebase — split out so a UI test process
/// can swap in a deterministic, network-free conformance instead of an in-process `URLProtocol`
/// mock.
protocol GitHubRepositoryService: Sendable {
    func repositories(credential: GitHubCredential) async throws -> [GitHubAPIClient.Repository]
    func refs(credential: GitHubCredential, owner: String, repo: String) async throws -> [GitHubRef]
    func pullRequests(credential: GitHubCredential, owner: String, repo: String) async throws -> [GitHubPullRequest]
    /// The old one-independent-clone-per-codebase sync, kept only for older codebases that were
    /// created against `ProjectStore.githubCloneURL(for:)` and still resolve their files there.
    @discardableResult
    func sync(
        _ target: GitHubRepositoryTarget, into destination: URL, onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> String

    /// Ensures a shared hub clone exists for `owner/repo` (creating it if this is the first
    /// codebase ever to reference it) and registers a brand-new linked worktree for one codebase.
    @discardableResult
    func attachWorktree(
        _ target: GitHubRepositoryTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> (headSHA: String, remoteURL: URL)

    /// Re-syncs the shared hub clone (a fetch, not a clone) to `ref` and moves an
    /// already-registered worktree along with it.
    @discardableResult
    func resyncWorktree(
        _ target: GitHubRepositoryTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> String
}

struct LiveGitHubRepositoryService: GitHubRepositoryService {
    func repositories(credential: GitHubCredential) async throws -> [GitHubAPIClient.Repository] {
        let client = GitHubAPIClient(credential: credential)
        var all: [GitHubAPIClient.Repository] = []
        var page = 1
        while true {
            let batch = try await client.repositories(page: page)
            all += batch
            guard batch.count == GitHubAPIClient.repositoriesPerPage else { break }
            page += 1
        }
        return all
    }

    func refs(credential: GitHubCredential, owner: String, repo: String) async throws -> [GitHubRef] {
        let client = GitHubAPIClient(credential: credential)
        async let branches = client.branches(owner: owner, repo: repo)
        async let tags = client.tags(owner: owner, repo: repo)
        return try await branches + tags
    }

    func pullRequests(credential: GitHubCredential, owner: String, repo: String) async throws -> [GitHubPullRequest] {
        try await GitHubAPIClient(credential: credential).pullRequests(owner: owner, repo: repo)
    }

    @discardableResult
    func sync(
        _ target: GitHubRepositoryTarget, into destination: URL, onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        try await GitHubRepositoryClone(
            credential: target.credential, owner: target.owner, repo: target.repo, ref: target.ref
        ).sync(into: destination, onProgress: onProgress)
    }

    @discardableResult
    func attachWorktree(
        _ target: GitHubRepositoryTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> (headSHA: String, remoteURL: URL) {
        let clone = GitHubRepositoryClone(
            credential: target.credential, owner: target.owner, repo: target.repo, ref: target.ref)
        let headSHA = try await GitWorktreeSync(
            transportURL: clone.authenticatedRemoteURL, ref: target.ref,
            hubStoreDirectory: destination.hubStoreDirectory, locks: destination.locks
        ).attachWorktree(named: destination.worktreeName, at: destination.worktreeDirectory, onProgress: onProgress)
        return (headSHA, clone.plainRemoteURL)
    }

    @discardableResult
    func resyncWorktree(
        _ target: GitHubRepositoryTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        let clone = GitHubRepositoryClone(
            credential: target.credential, owner: target.owner, repo: target.repo, ref: target.ref)
        return try await GitWorktreeSync(
            transportURL: clone.authenticatedRemoteURL, ref: target.ref,
            hubStoreDirectory: destination.hubStoreDirectory, locks: destination.locks
        ).resyncWorktree(at: destination.worktreeDirectory, onProgress: onProgress)
    }
}

/// Deterministic, network-free conformance for the snapshot tests' XCUITest journeys:
/// `repositories`/`refs` return canned data for the one local fixture repository, and `sync`
/// performs a real libgit2 clone/fetch (via `AcaiGit.GitClone`) against `remoteURL` — a local git
/// repository staged by the UI test — instead of `https://github.com/...`. Selected whenever
/// `UITestFixtureResolver().resolveBaseDir() != nil`, regardless of whether `remoteURL` is set —
/// otherwise a signed-in-only journey would fall through to `LiveGitHubRepositoryService` and hit
/// real network with a fake credential.
struct FixtureGitHubRepositoryService: GitHubRepositoryService {
    /// `nil` when no `-AcaiUITestGitHubRemoteURL` was configured — `refs`/`sync` throw a local
    /// `Failure` instead of falling back to network.
    let remoteURL: URL?

    enum Failure: LocalizedError {
        case noFixtureRemoteConfigured

        var errorDescription: String? {
            switch self {
            case .noFixtureRemoteConfigured:
                "No fixture GitHub remote configured for this UI test launch — pass "
                + "-AcaiUITestGitHubRemoteURL if this journey needs to list refs or clone."
            }
        }
    }

    static let repository = GitHubAPIClient.Repository(
        id: 1, name: "fixture-repo", fullName: "octocat/fixture-repo",
        owner: GitHubRepositoryOwner(login: "octocat"), defaultBranch: "main", isPrivate: false)

    func repositories(credential: GitHubCredential) async throws -> [GitHubAPIClient.Repository] {
        [Self.repository]
    }

    func refs(credential: GitHubCredential, owner: String, repo: String) async throws -> [GitHubRef] {
        guard let remoteURL else { throw Failure.noFixtureRemoteConfigured }
        return try GitCheckout(directory: remoteURL).refNames().map { name in
            GitHubRef(name: name, kind: .branch)
        }
    }

    /// An empty list rather than throwing, so a journey that merely opens the Compare panel sees an
    /// empty PR picker instead of an error.
    func pullRequests(credential: GitHubCredential, owner: String, repo: String) async throws -> [GitHubPullRequest] {
        []
    }

    @discardableResult
    func sync(
        _ target: GitHubRepositoryTarget, into destination: URL, onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        guard let remoteURL else { throw Failure.noFixtureRemoteConfigured }
        return try await GitClone(remoteURL: remoteURL, ref: target.ref)
            .sync(into: destination, onProgress: onProgress)
    }

    @discardableResult
    func attachWorktree(
        _ target: GitHubRepositoryTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> (headSHA: String, remoteURL: URL) {
        guard let remoteURL else { throw Failure.noFixtureRemoteConfigured }
        let headSHA = try await GitWorktreeSync(
            transportURL: remoteURL, ref: target.ref, hubStoreDirectory: destination.hubStoreDirectory,
            locks: destination.locks
        ).attachWorktree(named: destination.worktreeName, at: destination.worktreeDirectory, onProgress: onProgress)
        return (headSHA, remoteURL)
    }

    @discardableResult
    func resyncWorktree(
        _ target: GitHubRepositoryTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        guard let remoteURL else { throw Failure.noFixtureRemoteConfigured }
        return try await GitWorktreeSync(
            transportURL: remoteURL, ref: target.ref, hubStoreDirectory: destination.hubStoreDirectory,
            locks: destination.locks
        ).resyncWorktree(at: destination.worktreeDirectory, onProgress: onProgress)
    }
}

/// Network-free *and* git-free: `sync`/`attachWorktree`/`resyncWorktree` copy an already-staged
/// directory instead of running real libgit2 operations, so a journey that just needs a GitHub-
/// backed codebase to exist doesn't pay for git timing it isn't proving.
struct FastFixtureGitHubRepositoryService: GitHubRepositoryService {
    let sourceDirectoriesByRef: [String: URL]

    enum Failure: LocalizedError {
        case noStagedContent(ref: String)

        var errorDescription: String? {
            switch self {
            case .noStagedContent(let ref):
                "No staged fixture content for ref “\(ref)” — pass it to "
                + "GitFixtureRepository.makeCannedRemote(refs:)."
            }
        }
    }

    func repositories(credential: GitHubCredential) async throws -> [GitHubAPIClient.Repository] {
        [FixtureGitHubRepositoryService.repository]
    }

    func refs(credential: GitHubCredential, owner: String, repo: String) async throws -> [GitHubRef] {
        sourceDirectoriesByRef.keys.sorted().map { GitHubRef(name: $0, kind: .branch) }
    }

    func pullRequests(credential: GitHubCredential, owner: String, repo: String) async throws -> [GitHubPullRequest] {
        []
    }

    /// Not a real git SHA — nothing downstream validates the format, so a stable per-ref digest is
    /// enough.
    private func cannedSHA(for ref: String) -> String {
        SHA256.hash(data: Data(ref.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func stagedDirectory(for ref: String) throws -> URL {
        guard let url = sourceDirectoriesByRef[ref] else { throw Failure.noStagedContent(ref: ref) }
        return url
    }

    private func copyTree(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: destination)
    }

    @discardableResult
    func sync(
        _ target: GitHubRepositoryTarget, into destination: URL, onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        try copyTree(from: try stagedDirectory(for: target.ref), to: destination)
        onProgress?(1)
        return cannedSHA(for: target.ref)
    }

    @discardableResult
    func attachWorktree(
        _ target: GitHubRepositoryTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> (headSHA: String, remoteURL: URL) {
        try copyTree(from: try stagedDirectory(for: target.ref), to: destination.worktreeDirectory)
        onProgress?(1)
        let remoteURL = URL(string: "https://fixture.invalid/\(target.owner)/\(target.repo)")!
        return (cannedSHA(for: target.ref), remoteURL)
    }

    @discardableResult
    func resyncWorktree(
        _ target: GitHubRepositoryTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        try copyTree(from: try stagedDirectory(for: target.ref), to: destination.worktreeDirectory)
        onProgress?(1)
        return cannedSHA(for: target.ref)
    }
}

/// Picks between `LiveGitHubRepositoryService`, real-git `FixtureGitHubRepositoryService`, and
/// git-free `FastFixtureGitHubRepositoryService`.
struct GitHubRepositoryServiceResolver {
    func resolve() -> GitHubRepositoryService {
        guard UITestFixtureResolver().resolveBaseDir() != nil else { return LiveGitHubRepositoryService() }
        if let fastFixtureRoot = UITestFixtureResolver().resolveGitHubFastFixtureRoot() {
            let refDirectories = (try? FileManager.default.contentsOfDirectory(
                at: fastFixtureRoot, includingPropertiesForKeys: nil
            )) ?? []
            let sourceDirectoriesByRef = Dictionary(
                uniqueKeysWithValues: refDirectories.map { ($0.lastPathComponent, $0) })
            return FastFixtureGitHubRepositoryService(sourceDirectoriesByRef: sourceDirectoriesByRef)
        }
        return FixtureGitHubRepositoryService(remoteURL: UITestFixtureResolver().resolveGitHubRemoteURL())
    }
}
