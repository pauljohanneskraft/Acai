import Foundation

/// Validates that a codebase-relative path resolves to a real location inside a given root
/// directory, rejecting anything that would escape it. Any path resolved from external input (a
/// GitHub-sourced codebase's tree is not fully user-controlled) must be validated before use.
struct PathEscapeGuard {
    let root: URL

    enum Failure: LocalizedError {
        case absolutePath(String)
        case escapesRoot(String)

        var errorDescription: String? {
            switch self {
            case .absolutePath(let path):
                String(localized: .app("Error.PathEscapeGuard.AbsolutePath \(path)"))
            case .escapesRoot(let path):
                String(localized: .app("Error.PathEscapeGuard.EscapesRoot \(path)"))
            }
        }
    }

    /// Both the candidate and `root` are symlink-resolved before comparison — on macOS `root` itself
    /// is frequently a symlink (e.g. `/var` → `/private/var`), so resolving only one side would make
    /// a legitimately in-bounds path fail this check.
    func resolvedURL(forRelativePath relativePath: String) throws -> URL {
        // Reject absolute paths up front: `URL.appendingPathComponent` treats a leading "/" as a
        // plain path component, not as replacing the base, so a naive join-then-compare would
        // silently accept "/etc/passwd" as "root/etc/passwd" — which never escapes root and would
        // pass a prefix check. An absolute path must be rejected before it's ever joined.
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            throw Failure.absolutePath(relativePath)
        }

        let standardizedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let candidate = root
            .appendingPathComponent(relativePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL

        // Compare path components rather than string prefixes: a plain `hasPrefix` on `.path` would
        // accept a sibling directory that merely shares the root's path as a string prefix (e.g.
        // "/root-evil/x" against root "/root").
        let rootComponents = standardizedRoot.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.count >= rootComponents.count,
              Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
        else {
            throw Failure.escapesRoot(relativePath)
        }

        return candidate
    }
}
