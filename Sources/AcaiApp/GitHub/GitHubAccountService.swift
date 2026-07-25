import Foundation

/// The sign-in operations `GitHubAccountSection` needs — split out from `GitHubAPIClient`/
/// `GitHubDeviceAuthFlow` so a UI test process can swap in a deterministic, network-free
/// conformance instead of a `URLProtocol` mock. Scoped to sign-in only; other GitHub calls stay
/// direct `GitHubAPIClient(credential:)` calls until they need the same treatment.
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

/// Deterministic canned responses for the snapshot tests' XCUITest journeys — no network access.
/// Selected only when `UITestFixtureResolver().resolveBaseDir() != nil`.
struct FixtureGitHubAccountService: GitHubAccountService {
    /// The canned identity every fixture-stubbed sign-in resolves to.
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
