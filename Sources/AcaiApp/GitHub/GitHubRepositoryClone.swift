import AcaiGit
import Foundation

/// Clones (or re-syncs) a GitHub repository ref into an app-owned local folder as a real `git
/// clone` via `AcaiGit`, authenticated over HTTPS with the token embedded in the remote URL — no
/// `git` executable, no zipball download. The resulting folder is a plain directory indexed by
/// the same `CodebaseAnalyzer` path as any other codebase.
struct GitHubRepositoryClone {
    let credential: GitHubCredential
    let owner: String
    let repo: String
    /// A plain branch or tag name (not the REST API's `heads/`/`tags/`-qualified form).
    let ref: String

    /// Clones/syncs `destination` to `ref`'s current commit, replacing its contents only once the
    /// whole operation succeeds. Returns the ref's head commit SHA.
    @discardableResult
    func sync(into destination: URL) async throws -> String {
        try await GitClone(remoteURL: authenticatedRemoteURL, ref: ref).sync(into: destination)
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
}
