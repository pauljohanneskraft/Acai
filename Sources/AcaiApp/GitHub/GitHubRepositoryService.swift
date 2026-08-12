import Foundation
import AcaiGit

/// Where a repository-backed codebase's worktree should live and how its fetch/checkout against
/// the shared hub clone should be serialized — bundled (like `GitHubRepositoryRef`) to keep
/// `GitHubRepositoryService.attachWorktree`/`resyncWorktree` under the function-parameter-count
/// limit.
struct GitWorktreeDestination: Sendable {
    /// Where every shared hub clone lives, one subdirectory per remote — see
    /// `ProjectStore.gitRepositoriesDir`.
    var hubStoreDirectory: URL
    /// The libgit2 worktree name to register — see `ProjectStore.gitWorktreeName(for:)`. Unused by
    /// `resyncWorktree`, which moves an already-registered worktree rather than creating one.
    var worktreeName: String
    /// Where this codebase's linked worktree checkout lives — see `ProjectStore.gitWorktreeURL(for:)`.
    var worktreeDirectory: URL
    /// Serializes fetch-vs-checkout against the shared hub clone across every codebase referencing
    /// it — see `ProjectStore.gitRepositoryLocks`.
    var locks: GitRepositoryLocks
}

/// The repository/branch/tag/clone operations `NewCodebaseSheet`, `CodebaseDetailView`, and
/// `ProjectCodebaseEditor` need against a GitHub-backed codebase — split out (like
/// `GitHubAccountService`) so a UI test process can swap in a deterministic, network-free
/// conformance instead of an in-process `URLProtocol` mock.
protocol GitHubRepositoryService: Sendable {
    func repositories(credential: GitHubCredential) async throws -> [GitHubAPIClient.Repository]
    func refs(credential: GitHubCredential, owner: String, repo: String) async throws -> [GitHubRef]
    /// The old one-independent-clone-per-codebase sync, kept only for older codebases that were
    /// created against `ProjectStore.githubCloneURL(for:)` and still resolve their files there.
    @discardableResult
    func sync(
        credential: GitHubCredential, owner: String, repo: String, ref: String, into destination: URL
    ) async throws -> String

    /// Ensures a shared hub clone exists for `owner/repo` (creating it if this is the first
    /// codebase ever to reference it) and registers a brand-new linked worktree for one codebase.
    /// Returns the resolved commit SHA and the credential-free remote URL to persist in
    /// `CodebaseRepositoryReference`.
    @discardableResult
    func attachWorktree(
        credential: GitHubCredential, owner: String, repo: String, ref: String, destination: GitWorktreeDestination
    ) async throws -> (headSHA: String, remoteURL: URL)

    /// Re-syncs the shared hub clone (a fetch, not a clone) to `ref` and moves an
    /// already-registered worktree along with it — used by `pull`/`switchGitHubRef` once a
    /// codebase already has a worktree from `attachWorktree` above.
    @discardableResult
    func resyncWorktree(
        credential: GitHubCredential, owner: String, repo: String, ref: String, destination: GitWorktreeDestination
    ) async throws -> String
}

/// Real network calls — exactly what each call site did inline before this seam existed.
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

    @discardableResult
    func sync(
        credential: GitHubCredential, owner: String, repo: String, ref: String, into destination: URL
    ) async throws -> String {
        try await GitHubRepositoryClone(credential: credential, owner: owner, repo: repo, ref: ref)
            .sync(into: destination)
    }

    @discardableResult
    func attachWorktree(
        credential: GitHubCredential, owner: String, repo: String, ref: String, destination: GitWorktreeDestination
    ) async throws -> (headSHA: String, remoteURL: URL) {
        let clone = GitHubRepositoryClone(credential: credential, owner: owner, repo: repo, ref: ref)
        let headSHA = try await GitWorktreeSync(
            transportURL: clone.authenticatedRemoteURL, ref: ref, hubStoreDirectory: destination.hubStoreDirectory,
            locks: destination.locks
        ).attachWorktree(named: destination.worktreeName, at: destination.worktreeDirectory)
        return (headSHA, clone.plainRemoteURL)
    }

    @discardableResult
    func resyncWorktree(
        credential: GitHubCredential, owner: String, repo: String, ref: String, destination: GitWorktreeDestination
    ) async throws -> String {
        let clone = GitHubRepositoryClone(credential: credential, owner: owner, repo: repo, ref: ref)
        return try await GitWorktreeSync(
            transportURL: clone.authenticatedRemoteURL, ref: ref, hubStoreDirectory: destination.hubStoreDirectory,
            locks: destination.locks
        ).resyncWorktree(at: destination.worktreeDirectory)
    }
}

/// Deterministic, network-free conformance for the snapshot tests' XCUITest journeys:
/// `repositories`/`refs` return canned data for the one local fixture repository, and `sync`
/// performs a real libgit2 clone/fetch (via `AcaiGit.GitClone`) against `remoteURL` — a local git
/// repository staged by the UI test — instead of `https://github.com/...`. Selected whenever
/// `UITestFixtureResolver().resolveBaseDir() != nil`, regardless of whether `remoteURL` is set:
/// every UI-test-fixture launch must get the network-free conformance, even ones that never clone,
/// otherwise a signed-in-only journey would fall through to `LiveGitHubRepositoryService` and hit
/// real network with a fake credential.
struct FixtureGitHubRepositoryService: GitHubRepositoryService {
    /// `nil` when no `-AcaiUITestGitHubRemoteURL` was configured — `repositories(credential:)`
    /// doesn't need it; `refs`/`sync` throw a local `Failure` instead of falling back to network.
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

    /// The canned repository every fixture-stubbed picker resolves to.
    static let repository = GitHubAPIClient.Repository(
        id: 1, name: "fixture-repo", fullName: "octocat/fixture-repo",
        owner: GitHubRepositoryOwner(login: "octocat"), defaultBranch: "main", isPrivate: false)

    func repositories(credential: GitHubCredential) async throws -> [GitHubAPIClient.Repository] {
        [Self.repository]
    }

    /// Lists the fixture remote's actual local+tag refs (via `GitCheckout`) so the picker reflects
    /// whatever branches/tags the UI test's fixture repository actually created.
    func refs(credential: GitHubCredential, owner: String, repo: String) async throws -> [GitHubRef] {
        guard let remoteURL else { throw Failure.noFixtureRemoteConfigured }
        return try GitCheckout(directory: remoteURL).refNames().map { name in
            GitHubRef(name: name, kind: .branch)
        }
    }

    @discardableResult
    func sync(
        credential: GitHubCredential, owner: String, repo: String, ref: String, into destination: URL
    ) async throws -> String {
        guard let remoteURL else { throw Failure.noFixtureRemoteConfigured }
        return try await GitClone(remoteURL: remoteURL, ref: ref).sync(into: destination)
    }

    @discardableResult
    func attachWorktree(
        credential: GitHubCredential, owner: String, repo: String, ref: String, destination: GitWorktreeDestination
    ) async throws -> (headSHA: String, remoteURL: URL) {
        guard let remoteURL else { throw Failure.noFixtureRemoteConfigured }
        let headSHA = try await GitWorktreeSync(
            transportURL: remoteURL, ref: ref, hubStoreDirectory: destination.hubStoreDirectory,
            locks: destination.locks
        ).attachWorktree(named: destination.worktreeName, at: destination.worktreeDirectory)
        return (headSHA, remoteURL)
    }

    @discardableResult
    func resyncWorktree(
        credential: GitHubCredential, owner: String, repo: String, ref: String, destination: GitWorktreeDestination
    ) async throws -> String {
        guard let remoteURL else { throw Failure.noFixtureRemoteConfigured }
        return try await GitWorktreeSync(
            transportURL: remoteURL, ref: ref, hubStoreDirectory: destination.hubStoreDirectory,
            locks: destination.locks
        ).resyncWorktree(at: destination.worktreeDirectory)
    }
}

/// Picks between `LiveGitHubRepositoryService` and `FixtureGitHubRepositoryService` using the same
/// "is any UI test fixture active" check used elsewhere, factored out for three call sites
/// (`NewCodebaseSheet`, `CodebaseDetailView`, `ProjectCodebaseEditor`). The git-remote URL is a
/// separate, narrower signal passed through when present, never used to decide fixture-vs-live.
struct GitHubRepositoryServiceResolver {
    func resolve() -> GitHubRepositoryService {
        guard UITestFixtureResolver().resolveBaseDir() != nil else { return LiveGitHubRepositoryService() }
        return FixtureGitHubRepositoryService(remoteURL: UITestFixtureResolver().resolveGitHubRemoteURL())
    }
}
