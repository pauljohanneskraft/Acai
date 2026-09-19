import Foundation

/// A GitHub repository's HTTPS remote, authenticated with the token embedded in the URL — no `git`
/// executable, no zipball download.
struct GitHubRemote {
    let credential: GitHubCredential
    let owner: String
    let repo: String

    /// `https://x-access-token:{PAT}@github.com/{owner}/{repo}.git` — GitHub accepts any
    /// non-empty username paired with a valid token over HTTPS Basic auth.
    var authenticatedURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.user = "x-access-token"
        components.password = credential.token
        components.host = "github.com"
        components.path = "/\(owner)/\(repo).git"
        return components.url!
    }

    /// `https://github.com/{owner}/{repo}.git`, with no embedded credential — what's safe to persist
    /// in `CodebaseRepositoryReference.remoteURL`, unlike `authenticatedURL`, which must never be
    /// written to disk.
    var plainURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(owner)/\(repo).git"
        return components.url!
    }
}
