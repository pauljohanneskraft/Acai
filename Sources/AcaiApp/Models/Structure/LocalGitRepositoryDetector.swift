import AcaiGit
import Foundation

/// Detects whether a user-picked local folder is already a git working directory (or a
/// subdirectory of one) and, if so, resolves the `CodebaseRepositoryReference` that the
/// transparent local-folder upgrade records for it. Read-only: this never touches anything on
/// disk or starts a network operation. A plain, non-git folder — or a git repository with no
/// `origin` remote configured (nothing a shared `GitRepository` could sync against) — resolves to
/// `nil`, and the codebase keeps today's plain-directory behavior unchanged.
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

        return CodebaseRepositoryReference(remoteURL: remoteURL, ref: ref, subpath: subpath(root: root))
    }

    /// `nil` when `directory` *is* `root`; otherwise `directory`'s path relative to `root`.
    private func subpath(root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        guard directoryPath != rootPath else { return nil }
        guard directoryPath.hasPrefix(rootPath + "/") else { return nil }
        return String(directoryPath.dropFirst(rootPath.count + 1))
    }
}
