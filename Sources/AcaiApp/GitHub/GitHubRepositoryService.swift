import Foundation
import AcaiGit

/// The repository/branch/tag/clone operations `NewCodebaseSheet`, `CodebaseDetailView`, and
/// `ProjectCodebaseEditor` need against a GitHub-backed codebase — split out for the same reason
/// `GitHubAccountService` was: a UI test process can't share in-memory state with the app process,
/// so a deterministic, network-free conformance needs its own seam rather than an in-process
/// `URLProtocol` mock. Unlike sign-in, this seam was deliberately deferred when `GitHubAccountService`
/// was built (see that file's doc comment) until a "New Codebase from GitHub" journey was actually
/// prioritized — see `TESTING_ARCHITECTURE.md` Layer 2's GitHub journeys.
protocol GitHubRepositoryService: Sendable {
    func repositories(credential: GitHubCredential) async throws -> [GitHubAPIClient.Repository]
    func refs(credential: GitHubCredential, owner: String, repo: String) async throws -> [GitHubRef]
    @discardableResult
    func sync(
        credential: GitHubCredential, owner: String, repo: String, ref: String, into destination: URL
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
}

/// Deterministic, network-free conformance for Layer 2 XCUITest journeys: `repositories`/`refs`
/// return canned data describing the one local fixture repository, and `sync` performs a **real**
/// libgit2 clone/fetch (via `AcaiGit.GitClone`) against `remoteURL` — a local git repository staged
/// by the UI test — instead of `https://github.com/...`. This exercises the actual clone/fetch/
/// checkout code path end to end, deterministically, with no network access or credentials.
/// Selected whenever `UITestFixtureResolver().resolveBaseDir() != nil` — **not** gated on
/// `resolveGitHubRemoteURL()` (a real, empirically-found bug this replaced: a UI test that reaches a
/// signed-in state without itself needing to clone anything — e.g. `GitHubSignInTests`, which never
/// sets `-AcaiUITestGitHubRemoteURL` — got `LiveGitHubRepositoryService` instead, so
/// `NewCodebaseSheet`'s reactive `loadRepositories()` on sign-in made a **real** call to
/// `api.github.com` with the fixture's fake credential, surfacing a genuine "Bad credentials" 401 in
/// the UI. Any UI-test-fixture launch must always get the network-free conformance; `remoteURL`
/// being absent only limits which of *this struct's own methods* are usable, per method below).
struct FixtureGitHubRepositoryService: GitHubRepositoryService {
    /// `nil` when no `-AcaiUITestGitHubRemoteURL` was configured for this launch (i.e. the test
    /// doesn't exercise cloning) — `repositories(credential:)` doesn't need it at all; `refs`/`sync`
    /// throw a clear, local `Failure` instead of ever falling back to real network.
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

    /// The canned repository every fixture-stubbed picker resolves to. A single hardcoded entry is
    /// enough for the one journey that needs this today — see `FixtureGitHubAccountService.login`
    /// for the same "one canned identity is enough for now" reasoning.
    static let repository = GitHubAPIClient.Repository(
        id: 1, name: "fixture-repo", fullName: "octocat/fixture-repo",
        owner: GitHubRepositoryOwner(login: "octocat"), defaultBranch: "main", isPrivate: false)

    func repositories(credential: GitHubCredential) async throws -> [GitHubAPIClient.Repository] {
        [Self.repository]
    }

    /// Lists the fixture remote's actual local+tag refs (via `GitCheckout`) rather than a further
    /// hardcoded list, so the picker always reflects whatever branches/tags the UI test's
    /// `GitFixtureRepository` actually created.
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
}

/// Picks between `LiveGitHubRepositoryService` and `FixtureGitHubRepositoryService` — the same
/// one-signal check `GitHubAccountSection.init`/`GitHubTokenStore`/`DiagramThemeSelection` already
/// use ("is any UI test fixture active at all"), factored out since three call sites
/// (`NewCodebaseSheet`, `CodebaseDetailView`, `ProjectCodebaseEditor`) need it instead of just one.
/// The git-remote URL is a separate, narrower signal — passed through when present, but never used
/// to decide Fixture-vs-Live itself (see `FixtureGitHubRepositoryService`'s doc comment for the bug
/// that shape caused).
struct GitHubRepositoryServiceResolver {
    func resolve() -> GitHubRepositoryService {
        guard UITestFixtureResolver().resolveBaseDir() != nil else { return LiveGitHubRepositoryService() }
        return FixtureGitHubRepositoryService(remoteURL: UITestFixtureResolver().resolveGitHubRemoteURL())
    }
}
