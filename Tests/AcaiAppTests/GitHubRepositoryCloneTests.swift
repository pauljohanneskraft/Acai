import Foundation
import Testing
@testable import AcaiApp

// An extension of `GitHubNetworkingTests` (declared in `GitHubAPIClientTests.swift`), not a
// separate suite — see that file's `.serialized` comment for why these must share one suite.
extension GitHubNetworkingTests {
    /// `GitHubRepositoryClone`'s own responsibility, now that cloning goes through `AcaiGit`
    /// (covered end-to-end by `AcaiGitTests`) instead of downloading/extracting a zipball, is
    /// just building the right authenticated remote URL — the zipball-specific
    /// path-escape/symlink-safety tests this file used to have no longer apply (libgit2's own
    /// checkout handles that).
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
