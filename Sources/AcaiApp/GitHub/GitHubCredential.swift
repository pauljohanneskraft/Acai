import Foundation

/// How the app is authenticated to GitHub. Either shape is read-only by construction: a
/// `personalAccessToken` is expected to be a fine-grained PAT scoped to `Contents:Read-only`;
/// a `gitHubApp` token comes from a GitHub App registered with read-only permissions.
enum GitHubCredential: Codable, Hashable {
    case personalAccessToken(String)
    case gitHubApp(accessToken: String, expiresAt: Date?, refreshToken: String?)

    var authorizationHeaderValue: String {
        switch self {
        case .personalAccessToken(let token):
            "Bearer \(token)"
        case .gitHubApp(let accessToken, _, _):
            "Bearer \(accessToken)"
        }
    }

    /// The raw token value, embedded as the password in an authenticated `https://` git remote URL
    /// (`GitHubRepositoryClone`) — GitHub accepts any username paired with a valid token there.
    var token: String {
        switch self {
        case .personalAccessToken(let token):
            token
        case .gitHubApp(let accessToken, _, _):
            accessToken
        }
    }
}
