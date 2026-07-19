import Foundation

/// GitHub App device-flow sign-in: request a device code, show the user a short code plus a URL
/// to visit, then poll until they've authorized it. No client secret and no redirect URL needed —
/// device flow authenticates with the client ID alone (see `GitHubAppConfiguration` for the
/// one-time app registration this depends on).
struct GitHubDeviceAuthFlow {
    let clientID: String

    /// A pending sign-in: the code to show the user, where to enter it, and how long it's valid.
    struct DeviceCode {
        var deviceCode: String
        var userCode: String
        var verificationURI: URL
        var interval: TimeInterval
        var expiresAt: Date
    }

    enum Failure: LocalizedError {
        case expired
        case denied
        case server(String)

        var errorDescription: String? {
            switch self {
            case .expired:
                "The sign-in code expired. Try again."
            case .denied:
                "Sign-in was declined."
            case .server(let message):
                message
            }
        }
    }

    private enum PollOutcome: Error {
        case pending
        case slowDown
    }

    private struct DeviceCodeResponse: Decodable {
        let deviceCode: String
        let userCode: String
        let verificationUri: String
        let expiresIn: Int
        let interval: Int

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationUri = "verification_uri"
            case expiresIn = "expires_in"
            case interval
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Int?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case error
        }
    }

    /// `POST /login/device/code` — the first step, before anything is shown to the user.
    func requestDeviceCode() async throws -> DeviceCode {
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(["client_id": clientID])
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
        guard let verificationURL = URL(string: response.verificationUri) else {
            throw Failure.server("Invalid verification URL.")
        }
        return DeviceCode(
            deviceCode: response.deviceCode,
            userCode: response.userCode,
            verificationURI: verificationURL,
            interval: TimeInterval(response.interval),
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
    }

    /// Polls `POST /login/oauth/access_token` at `deviceCode.interval` until the user authorizes
    /// the code (or it expires/is denied), returning the resulting credential.
    func pollForCredential(_ deviceCode: DeviceCode) async throws -> GitHubCredential {
        var interval = deviceCode.interval
        while Date() < deviceCode.expiresAt {
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            do {
                return try await exchangeDeviceCode(deviceCode.deviceCode)
            } catch PollOutcome.pending {
                continue
            } catch PollOutcome.slowDown {
                interval += 5
            }
        }
        throw Failure.expired
    }

    /// `grant_type=refresh_token` — used by `GitHubCredential.refreshedIfNeeded` for an expired
    /// GitHub App user token.
    func refreshedCredential(refreshToken: String) async throws -> GitHubCredential {
        try await requestToken(formBody([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]))
    }

    private func exchangeDeviceCode(_ deviceCode: String) async throws -> GitHubCredential {
        try await requestToken(formBody([
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ]))
    }

    private func requestToken(_ body: Data) async throws -> GitHubCredential {
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        if let error = response.error {
            switch error {
            case "authorization_pending":
                throw PollOutcome.pending
            case "slow_down":
                throw PollOutcome.slowDown
            case "expired_token":
                throw Failure.expired
            case "access_denied":
                throw Failure.denied
            default:
                throw Failure.server(error)
            }
        }
        guard let accessToken = response.accessToken else {
            throw Failure.server("No access token in the response.")
        }
        let expiresAt = response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        return .gitHubApp(accessToken: accessToken, expiresAt: expiresAt, refreshToken: response.refreshToken)
    }

    private func formBody(_ parameters: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        return (components.percentEncodedQuery ?? "").data(using: .utf8) ?? Data()
    }
}
