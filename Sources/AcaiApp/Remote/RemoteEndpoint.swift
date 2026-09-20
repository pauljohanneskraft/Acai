import Foundation

/// A remote as git operations reach it. `remoteURL` is credential-free and safe to persist;
/// `transportURL` may embed a token and must never be written anywhere.
struct RemoteEndpoint: Sendable, Hashable {
    let remoteURL: URL
    let transportURL: URL

    /// A GitHub token is only ever sent to GitHub. Any other remote is reached anonymously, which
    /// covers public HTTPS remotes on every host.
    init(remoteURL: URL, gitHubCredential: GitHubCredential?) {
        self.remoteURL = remoteURL
        guard case .github(let owner, let repo) = RemoteHost(remoteURL: remoteURL), let gitHubCredential,
              remoteURL.scheme == "https"
        else {
            transportURL = remoteURL
            return
        }
        transportURL = GitHubRemote(credential: gitHubCredential, owner: owner, repo: repo).authenticatedURL
    }

    /// Reads the stored GitHub account, only for a GitHub remote.
    init(remoteURL: URL) {
        guard case .github = RemoteHost(remoteURL: remoteURL) else {
            self.init(remoteURL: remoteURL, gitHubCredential: nil)
            return
        }
        self.init(remoteURL: remoteURL, gitHubCredential: GitHubTokenStore().load()?.credential)
    }

    var host: RemoteHost { RemoteHost(remoteURL: remoteURL) }
}
