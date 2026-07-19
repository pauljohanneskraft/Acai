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

}
