import AcaiGit
import Foundation

/// Clones (or re-syncs) a GitHub repository ref into an app-owned local folder as a real `git
/// clone` — via `AcaiGit`, authenticated over HTTPS with the token embedded in the remote URL, no
/// `git` executable, no zipball download. Once cloned, the folder is a plain directory (with a
/// real `.git`) indexed by the same `CodebaseAnalyzer` path as any other codebase; GitHub is purely
/// how the folder got there.
struct GitHubRepositoryClone {
    let credential: GitHubCredential
    let owner: String
    let repo: String
    /// A plain branch or tag name (not GitHub's REST-API-qualified `heads/`/`tags/` form — the
    /// underlying `GitClone` disambiguates a branch/tag name itself).
    let ref: String

    /// Clones/syncs `destination` to `ref`'s current commit, replacing its contents (if any) only
    /// once the whole operation has fully succeeded — a failed sync leaves whatever was there
    /// before untouched. Returns the ref's head commit SHA.
    @discardableResult
    func sync(into destination: URL) async throws -> String {
        try await GitClone(remoteURL: authenticatedRemoteURL, ref: ref).sync(into: destination)
    }

    /// `https://x-access-token:{PAT}@github.com/{owner}/{repo}.git` — GitHub accepts any
    /// non-empty username paired with a valid token over HTTPS Basic auth; libgit2's HTTP
    /// transport authenticates directly from a URL's embedded userinfo, no credentials callback
    /// needed.
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
