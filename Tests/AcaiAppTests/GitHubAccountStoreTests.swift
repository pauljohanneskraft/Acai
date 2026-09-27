import Foundation
import Testing
@testable import AcaiApp

@Suite("GitHubAccountStore", .timeLimit(.minutes(1)))
@MainActor
struct GitHubAccountStoreTests {
    private struct RejectedToken: Error {}

    private struct RejectingGitHubAccountService: GitHubAccountService {
        func authenticatedUserInfo(credential: GitHubCredential) async throws -> GitHubAPIClient.AuthenticatedUserInfo {
            throw RejectedToken()
        }

        func requestDeviceCode(clientID: String) async throws -> GitHubDeviceAuthFlow.DeviceCode {
            throw RejectedToken()
        }

        func pollForCredential(
            _ deviceCode: GitHubDeviceAuthFlow.DeviceCode, clientID: String
        ) async throws -> GitHubCredential {
            throw RejectedToken()
        }
    }

    private func makeTokenFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-github-account-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("github-token.json")
    }

    @Test func signingInPersistsLoginAndScopes() async throws {
        let tokenFile = try makeTokenFile()
        defer { try? FileManager.default.removeItem(at: tokenFile.deletingLastPathComponent()) }
        let tokenStore = GitHubTokenStore(fileURL: tokenFile)
        let store = GitHubAccountStore(service: FixtureGitHubAccountService(), tokenStore: tokenStore)
        #expect(store.account == nil)

        try await store.signIn(with: .personalAccessToken("t"))

        #expect(store.account?.login == FixtureGitHubAccountService.login)
        #expect(store.account?.scopes == ["contents:read", "metadata:read"])
        #expect(store.account?.credential == .personalAccessToken("t"))
        #expect(tokenStore.load() == store.account)
        let relaunched = GitHubAccountStore(service: FixtureGitHubAccountService(), tokenStore: tokenStore)
        #expect(relaunched.account == store.account)
    }

    @Test func signOutClearsStoredAndPublishedAccount() async throws {
        let tokenFile = try makeTokenFile()
        defer { try? FileManager.default.removeItem(at: tokenFile.deletingLastPathComponent()) }
        let tokenStore = GitHubTokenStore(fileURL: tokenFile)
        let store = GitHubAccountStore(service: FixtureGitHubAccountService(), tokenStore: tokenStore)
        try await store.signIn(with: .personalAccessToken("t"))
        #expect(FileManager.default.fileExists(atPath: tokenFile.path))

        store.signOut()

        #expect(store.account == nil)
        #expect(tokenStore.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: tokenFile.path))
    }

    @Test func aFailedRefreshKeepsKnownScopes() async throws {
        let tokenFile = try makeTokenFile()
        defer { try? FileManager.default.removeItem(at: tokenFile.deletingLastPathComponent()) }
        let tokenStore = GitHubTokenStore(fileURL: tokenFile)
        let store = GitHubAccountStore(service: RejectingGitHubAccountService(), tokenStore: tokenStore)
        let known = GitHubTokenStore.StoredAccount(
            credential: .personalAccessToken("t"), login: "octocat", scopes: ["repo"],
            tokenExpiresAt: Date(timeIntervalSince1970: 1_700_000_000))
        try store.signIn(known)

        await store.refreshScopes()

        #expect(store.account == known)
        #expect(tokenStore.load() == known)
        #expect(!store.isRefreshingScopes)
    }

    @Test func aRejectedTokenLeavesSignedOut() async throws {
        let tokenFile = try makeTokenFile()
        defer { try? FileManager.default.removeItem(at: tokenFile.deletingLastPathComponent()) }
        let tokenStore = GitHubTokenStore(fileURL: tokenFile)
        let store = GitHubAccountStore(service: RejectingGitHubAccountService(), tokenStore: tokenStore)

        await #expect(throws: RejectedToken.self) {
            try await store.signIn(with: .personalAccessToken("bad"))
        }

        #expect(store.account == nil)
        #expect(tokenStore.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: tokenFile.path))
    }

    /// The literal a journey writes to pre-seed a signed-in launch, pinned here so the on-disk
    /// format can't drift away from it unnoticed.
    @Test func loadsAPreSeededTokenFile() throws {
        let tokenFile = try makeTokenFile()
        defer { try? FileManager.default.removeItem(at: tokenFile.deletingLastPathComponent()) }
        let literal = #"{"credential":{"personalAccessToken":{"_0":"t"}},"login":"octocat"}"#
        try Data(literal.utf8).write(to: tokenFile)

        let store = GitHubAccountStore(
            service: FixtureGitHubAccountService(), tokenStore: GitHubTokenStore(fileURL: tokenFile))

        #expect(store.account?.login == "octocat")
        #expect(store.account?.credential == .personalAccessToken("t"))
        #expect(store.account?.scopes == nil)
    }
}
