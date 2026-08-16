import AcaiGit
import Foundation

/// Clones (or re-syncs) a GitHub repository ref into an app-owned local folder as a real `git
/// clone` via `AcaiGit`, authenticated over HTTPS with the token embedded in the remote URL — no
/// `git` executable, no zipball download.
struct GitHubRepositoryClone {
    let credential: GitHubCredential
    let owner: String
    let repo: String
    /// A plain branch or tag name (not the REST API's `heads/`/`tags/`-qualified form).
    let ref: String

    @discardableResult
    func sync(into destination: URL, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        try await GitClone(remoteURL: authenticatedRemoteURL, ref: ref).sync(into: destination, onProgress: onProgress)
    }

    /// `https://x-access-token:{PAT}@github.com/{owner}/{repo}.git` — GitHub accepts any
    /// non-empty username paired with a valid token over HTTPS Basic auth.
    var authenticatedRemoteURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.user = "x-access-token"
        components.password = credential.token
        components.host = "github.com"
        components.path = "/\(owner)/\(repo).git"
        return components.url!
    }

    /// `https://github.com/{owner}/{repo}.git`, with no embedded credential — what's actually safe
    /// to persist in `CodebaseRepositoryReference.remoteURL`, unlike
    /// `authenticatedRemoteURL` above, which must never be written to disk.
    var plainRemoteURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(owner)/\(repo).git"
        return components.url!
    }
}
