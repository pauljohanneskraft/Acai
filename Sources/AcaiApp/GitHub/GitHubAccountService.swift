import Foundation

/// The sign-in operations `GitHubAccountSection` needs — split out so a UI test process can swap
/// in a deterministic, network-free conformance instead of a `URLProtocol` mock.
protocol GitHubAccountService: Sendable {
    func authenticatedUserInfo(credential: GitHubCredential) async throws -> GitHubAPIClient.AuthenticatedUserInfo
    func requestDeviceCode(clientID: String) async throws -> GitHubDeviceAuthFlow.DeviceCode
    func pollForCredential(
        _ deviceCode: GitHubDeviceAuthFlow.DeviceCode, clientID: String
    ) async throws -> GitHubCredential
}

struct LiveGitHubAccountService: GitHubAccountService {
    func authenticatedUserInfo(credential: GitHubCredential) async throws -> GitHubAPIClient.AuthenticatedUserInfo {
        try await GitHubAPIClient(credential: credential).authenticatedUserWithMetadata()
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
    static let login = "octocat"

    func authenticatedUserInfo(credential: GitHubCredential) async throws -> GitHubAPIClient.AuthenticatedUserInfo {
        GitHubAPIClient.AuthenticatedUserInfo(
            user: GitHubAPIClient.User(login: Self.login, avatarURL: nil),
            scopes: ["contents:read", "metadata:read"],
            tokenExpiresAt: nil
        )
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
