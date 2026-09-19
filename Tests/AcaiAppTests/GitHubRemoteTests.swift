import Foundation
import Testing
@testable import AcaiApp

extension GitHubNetworkingTests {
    @Test func authenticatedRemoteURLEmbedsTokenAndPath() {
        let remote = GitHubRemote(credential: .personalAccessToken("secret-token"), owner: "acme", repo: "widgets")

        let url = remote.authenticatedURL

        #expect(url.scheme == "https")
        #expect(url.host == "github.com")
        #expect(url.user == "x-access-token")
        #expect(url.password == "secret-token")
        #expect(url.path == "/acme/widgets.git")
    }

    @Test func authenticatedRemoteURLUsesGitHubAppAccessToken() {
        let remote = GitHubRemote(
            credential: .gitHubApp(accessToken: "app-token", expiresAt: nil, refreshToken: nil),
            owner: "acme", repo: "widgets")

        #expect(remote.authenticatedURL.password == "app-token")
    }

    @Test func plainRemoteURLCarriesNoCredential() {
        let remote = GitHubRemote(credential: .personalAccessToken("secret-token"), owner: "acme", repo: "widgets")

        #expect(remote.plainURL.absoluteString == "https://github.com/acme/widgets.git")
    }
}
