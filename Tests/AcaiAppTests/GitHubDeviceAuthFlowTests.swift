import AcaiTestSupport
import Foundation
import Testing
@testable import AcaiApp

extension GitHubNetworkingTests {

    private func makeFlow() -> GitHubDeviceAuthFlow {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return GitHubDeviceAuthFlow(clientID: "client-id", session: URLSession(configuration: configuration))
    }

    /// A near-instant `interval` so tests don't wait out real poll delays, and an expiry far enough
    /// out that it never bounds them — expiry is its own test's subject, not a budget these share.
    private func makeDeviceCode(
        interval: TimeInterval = 0.01, expiresIn: TimeInterval = 600
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
        let attempt = Locked(0)
        MockURLProtocol.handler = { _ in
            let count = attempt.withValue { $0 += 1; return $0 }
            if count < 3 {
                return try self.tokenResponse(["error": "authorization_pending"])
            }
            return try self.tokenResponse(["access_token": "abc123"])
        }
        defer { MockURLProtocol.handler = nil }

        let flow = makeFlow()
        let credential = try await flow.pollForCredential(makeDeviceCode())

        #expect(credential == .gitHubApp(accessToken: "abc123", expiresAt: nil, refreshToken: nil))
        #expect(attempt.value == 3)
    }

    @Test func pollForCredentialRetriesThroughTransientNetworkErrorThenSucceeds() async throws {
        let attempt = Locked(0)
        MockURLProtocol.handler = { _ in
            let count = attempt.withValue { $0 += 1; return $0 }
            if count == 1 {
                throw URLError(.networkConnectionLost)
            }
            return try self.tokenResponse(["access_token": "abc123"])
        }
        defer { MockURLProtocol.handler = nil }

        let flow = makeFlow()
        let credential = try await flow.pollForCredential(makeDeviceCode())

        #expect(credential == .gitHubApp(accessToken: "abc123", expiresAt: nil, refreshToken: nil))
        #expect(attempt.value == 2)
    }

    @Test func pollForCredentialStopsImmediatelyOnTerminalOutcome() async throws {
        let attempt = Locked(0)
        MockURLProtocol.handler = { _ in
            attempt.withValue { $0 += 1 }
            return try self.tokenResponse(["error": "access_denied"])
        }
        defer { MockURLProtocol.handler = nil }

        let flow = makeFlow()
        await #expect(throws: GitHubDeviceAuthFlow.Failure.self) {
            _ = try await flow.pollForCredential(makeDeviceCode())
        }
        #expect(attempt.value == 1)
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
