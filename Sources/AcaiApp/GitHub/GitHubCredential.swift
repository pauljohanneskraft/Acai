import Foundation

/// How the app is authenticated to GitHub. Either shape is read-only by construction, not by
/// app-side self-restraint alone: a `personalAccessToken` is expected to be a fine-grained PAT the
/// user scoped to `Contents:Read-only` on github.com; a `gitHubApp` token comes from a GitHub App
/// whose permissions were declared read-only (`Contents`/`Metadata: Read-only`) at registration.
enum GitHubCredential: Codable, Hashable {
    case personalAccessToken(String)
    case gitHubApp(accessToken: String, expiresAt: Date?, refreshToken: String?)

    /// The `Authorization` header value to send on every GitHub API request.
    var authorizationHeaderValue: String {
        switch self {
        case .personalAccessToken(let token):
            "Bearer \(token)"
        case .gitHubApp(let accessToken, _, _):
            "Bearer \(accessToken)"
        }
    }

    /// `true` once the stored expiry has passed. Always `false` for a PAT, which GitHub doesn't
    /// expire this way.
    var isExpired: Bool {
        guard case .gitHubApp(_, let expiresAt, _) = self, let expiresAt else { return false }
        return expiresAt < Date()
    }
}

extension GitHubCredential {
    /// Returns a refreshed credential if this is an expired GitHub App token with a refresh token
    /// on hand, using `flow` to perform the actual refresh call; otherwise returns `self`
    /// unchanged (the common case — a PAT, or a still-valid App token).
    func refreshedIfNeeded(using flow: GitHubDeviceAuthFlow) async throws -> GitHubCredential {
        guard case .gitHubApp(_, let expiresAt, let refreshToken) = self,
              let expiresAt, expiresAt < Date(),
              let refreshToken else {
            return self
        }
        return try await flow.refreshedCredential(refreshToken: refreshToken)
    }
}
