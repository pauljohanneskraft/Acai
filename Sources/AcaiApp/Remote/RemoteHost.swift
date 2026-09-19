import Foundation

/// Which provider, if any, contributes host-specific conveniences (repository browsing, change
/// requests, size estimates) on top of a remote. Everything that only needs git works for
/// `.generic` too. Adding a provider means adding a case here, not changing what is persisted.
enum RemoteHost: Hashable {
    case github(owner: String, repo: String)
    case generic

    init(remoteURL: URL) {
        let host = remoteURL.host?.lowercased()
        let components = remoteURL.path.split(separator: "/").map(String.init)
        guard host == "github.com" || host == "www.github.com", components.count == 2 else {
            self = .generic
            return
        }
        let repo = components[1].hasSuffix(".git") ? String(components[1].dropLast(4)) : components[1]
        self = .github(owner: components[0], repo: repo)
    }
}

extension CodebaseRepositoryReference {
    var host: RemoteHost { RemoteHost(remoteURL: remoteURL) }

    /// `host/path` for a network remote (`github.com/acme/widgets`), the path for a local one.
    var remoteDisplayName: String {
        let path = remoteURL.path.hasSuffix(".git") ? String(remoteURL.path.dropLast(4)) : remoteURL.path
        guard let host = remoteURL.host, !remoteURL.isFileURL else { return path }
        return host + path
    }
}
