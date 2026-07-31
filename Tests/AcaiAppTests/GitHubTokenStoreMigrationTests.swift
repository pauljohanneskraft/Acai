import Foundation
import Testing
@testable import AcaiApp

/// Adding `scopes`/`tokenExpiresAt` to `GitHubTokenStore.StoredAccount` requires proof (not just
/// the "Optional fields decode fine" reasoning) that an already-persisted
/// account, saved before those fields existed, still decodes rather than throwing or silently
/// corrupting the stored credential.
@Suite("GitHubTokenStore.StoredAccount migration")
struct GitHubTokenStoreMigrationTests {
    /// Exactly `StoredAccount`'s shape before `scopes`/`tokenExpiresAt` existed — produced by
    /// actually encoding this legacy shape (rather than a hand-typed JSON literal guessing at
    /// `GitHubCredential`'s synthesized enum encoding) so the fixture is provably accurate to what
    /// an older app build really persisted.
    private struct LegacyStoredAccount: Codable {
        var credential: GitHubCredential
        var login: String
        var avatarURL: URL?
    }

    @Test func decodesLegacyJSONWithoutScopesOrExpiry() throws {
        let legacy = LegacyStoredAccount(credential: .personalAccessToken("legacy-token"), login: "octocat")
        let data = try JSONEncoder().encode(legacy)
        let account = try JSONDecoder().decode(GitHubTokenStore.StoredAccount.self, from: data)

        #expect(account.login == "octocat")
        #expect(account.credential == .personalAccessToken("legacy-token"))
        #expect(account.scopes == nil)
        #expect(account.tokenExpiresAt == nil)
    }

    @Test func roundTripsWithScopesAndExpiryPopulated() throws {
        let expiry = Date(timeIntervalSince1970: 1_700_000_000)
        let original = GitHubTokenStore.StoredAccount(
            credential: .personalAccessToken("t"), login: "octocat", avatarURL: nil,
            scopes: ["contents:read", "metadata:read"], tokenExpiresAt: expiry)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitHubTokenStore.StoredAccount.self, from: data)

        #expect(decoded == original)
    }
}
