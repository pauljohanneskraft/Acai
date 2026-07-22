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
/// Selected only when `UITestFixtureResolver().resolveGitHubRemoteURL() != nil`.
struct FixtureGitHubRepositoryService: GitHubRepositoryService {
    let remoteURL: URL

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
        try GitCheckout(directory: remoteURL).refNames().map { name in
            GitHubRef(name: name, kind: .branch)
        }
    }

    @discardableResult
    func sync(
        credential: GitHubCredential, owner: String, repo: String, ref: String, into destination: URL
    ) async throws -> String {
        try await GitClone(remoteURL: remoteURL, ref: ref).sync(into: destination)
    }
}

/// Picks between `LiveGitHubRepositoryService` and `FixtureGitHubRepositoryService` — the same
/// one-signal check `GitHubAccountSection.init` already uses for sign-in, factored out since three
/// call sites (`NewCodebaseSheet`, `CodebaseDetailView`, `ProjectCodebaseEditor`) need it instead of
/// just one.
struct GitHubRepositoryServiceResolver {
    func resolve() -> GitHubRepositoryService {
        if let remoteURL = UITestFixtureResolver().resolveGitHubRemoteURL() {
            return FixtureGitHubRepositoryService(remoteURL: remoteURL)
        }
        return LiveGitHubRepositoryService()
    }
}
