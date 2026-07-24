import Foundation

/// The sign-in operations `GitHubAccountSection` needs — split out from `GitHubAPIClient`/
/// `GitHubDeviceAuthFlow` so a UI test process (which can't share in-memory state with the app
/// process the way `@testable import` + a `URLProtocol` mock can for in-process Layer 0 tests) can
/// swap in a deterministic, network-free conformance instead. Deliberately scoped to sign-in only —
/// the repository/branch/tag/clone calls elsewhere (`NewCodebaseSheet`, `ProjectBrowserDiagramEditors`,
/// `CodebaseDetailView`) aren't part of any gated journey yet, so they stay direct
/// `GitHubAPIClient(credential:)` calls until that changes. See `TESTING_ARCHITECTURE.md` Layer 2.
protocol GitHubAccountService: Sendable {
    func authenticatedUser(credential: GitHubCredential) async throws -> GitHubAPIClient.User
    func requestDeviceCode(clientID: String) async throws -> GitHubDeviceAuthFlow.DeviceCode
    func pollForCredential(
        _ deviceCode: GitHubDeviceAuthFlow.DeviceCode, clientID: String
    ) async throws -> GitHubCredential
}

/// Real network calls — exactly what `GitHubAccountSection` did inline before this seam existed.
struct LiveGitHubAccountService: GitHubAccountService {
    func authenticatedUser(credential: GitHubCredential) async throws -> GitHubAPIClient.User {
        try await GitHubAPIClient(credential: credential).authenticatedUser()
    }

    func requestDeviceCode(clientID: String) async throws -> GitHubDeviceAuthFlow.DeviceCode {
        try await GitHubDeviceAuthFlow(clientID: clientID).requestDeviceCode()
    }

    func pollForCredential(
        _ deviceCode: GitHubDeviceAuthFlow.DeviceCode, clientID: String
    ) async throws -> GitHubCredential {
        try await GitHubDeviceAuthFlow(clientID: clientID).pollForCredential(deviceCode)
    }
}

/// Deterministic canned responses for Layer 2 XCUITest journeys — no network access at all.
/// Selected only when `UITestFixtureResolver().resolveBaseDir() != nil`, mirroring the same check
/// `ProjectStore.init` already uses to redirect its own storage.
struct FixtureGitHubAccountService: GitHubAccountService {
    /// The canned identity every fixture-stubbed sign-in resolves to. A single hardcoded identity
    /// is enough for the one journey that needs this today; move to fixture-specific JSON (like
    /// `ProjectStore`'s `projects/*.json`) if a second journey ever needs a different one.
    static let login = "octocat"

    func authenticatedUser(credential: GitHubCredential) async throws -> GitHubAPIClient.User {
        GitHubAPIClient.User(login: Self.login, avatarURL: nil)
    }

    func requestDeviceCode(clientID: String) async throws -> GitHubDeviceAuthFlow.DeviceCode {
        GitHubDeviceAuthFlow.DeviceCode(
            deviceCode: "fixture-device-code",
            userCode: "FIXTURE-CODE",
            verificationURI: URL(string: "https://github.com/login/device")!,
            interval: 0,
            expiresAt: Date().addingTimeInterval(900)
        )
    }

    func pollForCredential(
        _ deviceCode: GitHubDeviceAuthFlow.DeviceCode, clientID: String
    ) async throws -> GitHubCredential {
        .personalAccessToken("ui-test-fixture-token")
    }
}
