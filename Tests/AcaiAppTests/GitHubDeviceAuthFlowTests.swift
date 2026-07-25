import Foundation
import Testing
@testable import AcaiApp

// An extension of `GitHubNetworkingTests` (declared in `GitHubAPIClientTests.swift`), not a
// separate suite — see that file's `.serialized` comment for why these must share one suite.
extension GitHubNetworkingTests {

    private func makeFlow() -> GitHubDeviceAuthFlow {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return GitHubDeviceAuthFlow(clientID: "client-id", session: URLSession(configuration: configuration))
    }

    /// A short-lived code so tests don't actually wait out `interval`s.
    private func makeDeviceCode(
        interval: TimeInterval = 0.01, expiresIn: TimeInterval = 5
    ) -> GitHubDeviceAuthFlow.DeviceCode {
        GitHubDeviceAuthFlow.DeviceCode(
            deviceCode: "device-code",
            userCode: "USER-CODE",
            verificationURI: URL(string: "https://github.com/login/device")!,
            interval: interval,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    private func tokenResponse(_ body: [String: String]) throws -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "https://github.com/login/oauth/access_token")!,
            statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        return (response, try JSONEncoder().encode(body))
    }

    @Test func pollForCredentialRetriesThroughAuthorizationPendingThenSucceeds() async throws {
        nonisolated(unsafe) var attempt = 0
        MockURLProtocol.handler = { _ in
            attempt += 1
            if attempt < 3 {
                return try self.tokenResponse(["error": "authorization_pending"])
            }
            return try self.tokenResponse(["access_token": "abc123"])
        }
        defer { MockURLProtocol.handler = nil }

        let flow = makeFlow()
        let credential = try await flow.pollForCredential(makeDeviceCode())

        #expect(credential == .gitHubApp(accessToken: "abc123", expiresAt: nil, refreshToken: nil))
        #expect(attempt == 3)
    }

    @Test func pollForCredentialRetriesThroughTransientNetworkErrorThenSucceeds() async throws {
        nonisolated(unsafe) var attempt = 0
        MockURLProtocol.handler = { _ in
            attempt += 1
            if attempt == 1 {
                throw URLError(.networkConnectionLost)
            }
            return try self.tokenResponse(["access_token": "abc123"])
        }
        defer { MockURLProtocol.handler = nil }

        let flow = makeFlow()
        let credential = try await flow.pollForCredential(makeDeviceCode())

        #expect(credential == .gitHubApp(accessToken: "abc123", expiresAt: nil, refreshToken: nil))
        #expect(attempt == 2)
    }

    @Test func pollForCredentialStopsImmediatelyOnTerminalOutcome() async throws {
        nonisolated(unsafe) var attempt = 0
        MockURLProtocol.handler = { _ in
            attempt += 1
            return try self.tokenResponse(["error": "access_denied"])
        }
        defer { MockURLProtocol.handler = nil }

        let flow = makeFlow()
        await #expect(throws: GitHubDeviceAuthFlow.Failure.self) {
            _ = try await flow.pollForCredential(makeDeviceCode())
        }
        #expect(attempt == 1)
    }

    @Test func pollForCredentialPropagatesPromptlyWhenCancelled() async throws {
        MockURLProtocol.handler = { _ in try self.tokenResponse(["error": "authorization_pending"]) }
        defer { MockURLProtocol.handler = nil }

        let flow = makeFlow()
        // A long-lived code (unlike the other tests) so the only way this task ends is cancellation,
        // not natural expiry — proving the poll loop actually reacts to cancellation rather than
        // happening to finish around the same time.
        let deviceCode = makeDeviceCode(interval: 0.01, expiresIn: 60)
        let task = Task { try await flow.pollForCredential(deviceCode) }
        task.cancel()

        await #expect(throws: (any Error).self) {
            _ = try await task.value
        }
    }
}
