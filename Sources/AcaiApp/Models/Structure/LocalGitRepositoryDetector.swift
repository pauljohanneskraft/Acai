import AcaiGit
import Foundation

/// Detects whether a user-picked local folder is already a git working directory (or a
/// subdirectory of one) and, if so, resolves the `CodebaseRepositoryReference` for it. Read-only:
/// never touches anything on disk or starts a network operation. A plain, non-git folder — or a
/// git repository with no `origin` remote configured — resolves to `nil`.
struct LocalGitRepositoryDetector {
    let directory: URL

    func detect() -> CodebaseRepositoryReference? {
        guard let root = GitRepositoryRoot(directory: directory).find() else { return nil }

        let checkout: GitCheckout
        do {
            checkout = try GitCheckout(directory: directory)
        } catch {
            return nil
        }

        guard let remoteURL = checkout.originRemoteURL, let ref = try? checkout.currentRef else {
            return nil
        }

        return CodebaseRepositoryReference(
            remoteURL: withoutCredentials(remoteURL), ref: ref, subpath: subpath(root: root))
    }

    /// An `origin` may embed a token (`https://user:token@host/…`); persisted state never does.
    private func withoutCredentials(_ url: URL) -> URL {
        guard url.user != nil || url.password != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.user = nil
        components.password = nil
        return components.url ?? url
    }

    private func subpath(root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        guard directoryPath != rootPath else { return nil }
        guard directoryPath.hasPrefix(rootPath + "/") else { return nil }
        return String(directoryPath.dropFirst(rootPath.count + 1))
    }
}
