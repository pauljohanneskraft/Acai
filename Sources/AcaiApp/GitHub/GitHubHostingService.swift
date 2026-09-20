import Foundation

/// GitHub's contribution on top of a plain git remote: browsing the signed-in account's
/// repositories and listing a repository's open pull requests. Cloning, fetching and switching
/// revision are `GitRemoteService`'s, and work without this.
protocol GitHubHostingService: Sendable {
    func repositories(credential: GitHubCredential) async throws -> [GitHubAPIClient.Repository]
    func pullRequests(credential: GitHubCredential, owner: String, repo: String) async throws -> [ChangeRequest]
}

struct LiveGitHubHostingService: GitHubHostingService {
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

    func pullRequests(credential: GitHubCredential, owner: String, repo: String) async throws -> [ChangeRequest] {
        try await GitHubAPIClient(credential: credential).pullRequests(owner: owner, repo: repo)
    }
}

/// Canned data for the UI tests' single fixture repository. Its reported size comes from
/// `UITestFixtureResolver.gitHubRepositorySizeVariable`, so a journey can make it "large".
struct FixtureGitHubHostingService: GitHubHostingService {
    var repositorySizeKilobytes: Int = 1

    var repository: GitHubAPIClient.Repository {
        GitHubAPIClient.Repository(
            id: 1, name: "fixture-repo", fullName: "octocat/fixture-repo",
            owner: GitHubRepositoryOwner(login: "octocat"), defaultBranch: "main", isPrivate: false,
            sizeKilobytes: repositorySizeKilobytes)
    }

    func repositories(credential: GitHubCredential) async throws -> [GitHubAPIClient.Repository] {
        [repository]
    }

    /// Empty rather than throwing, so a journey that merely opens the Compare panel sees an empty
    /// change-request list instead of an error.
    func pullRequests(credential: GitHubCredential, owner: String, repo: String) async throws -> [ChangeRequest] {
        []
    }
}

struct GitHubHostingServiceResolver {
    func resolve() -> GitHubHostingService {
        let fixtures = UITestFixtureResolver()
        guard fixtures.resolveBaseDir() != nil else { return LiveGitHubHostingService() }
        return FixtureGitHubHostingService(
            repositorySizeKilobytes: fixtures.resolveGitHubRepositorySizeKilobytes() ?? 1)
    }
}
