import Foundation
import Testing
@testable import AcaiApp

// Extension of `GitHubNetworkingTests`, not a separate suite — see that file's `.serialized`
// comment for why these must share one suite.
extension GitHubNetworkingTests {
    /// `GitHubRepositoryClone` just builds the authenticated remote URL; cloning itself goes
    /// through `AcaiGit`/libgit2, covered by `AcaiGitTests`.
    @Test func authenticatedRemoteURLEmbedsTokenAndPath() {
        let clone = GitHubRepositoryClone(
            credential: .personalAccessToken("secret-token"), owner: "acme", repo: "widgets", ref: "main")

        let url = clone.authenticatedRemoteURL

        #expect(url.scheme == "https")
        #expect(url.host == "github.com")
        #expect(url.user == "x-access-token")
        #expect(url.password == "secret-token")
        #expect(url.path == "/acme/widgets.git")
    }

    @Test func authenticatedRemoteURLUsesGitHubAppAccessToken() {
        let clone = GitHubRepositoryClone(
            credential: .gitHubApp(accessToken: "app-token", expiresAt: nil, refreshToken: nil),
            owner: "acme", repo: "widgets", ref: "main")

        #expect(clone.authenticatedRemoteURL.password == "app-token")
    }
}
