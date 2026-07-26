import Foundation

extension Codebase {
    enum ResolvedFileURLFailure: LocalizedError {
        case absolutePath(String)
        case pathEscapesCodebaseRoot(String)

        var errorDescription: String? {
            switch self {
            case .absolutePath(let path):
                "\"\(path)\" must be relative to the codebase's directory, not an absolute path."
            case .pathEscapesCodebaseRoot(let path):
                "\"\(path)\" is outside the codebase's directory."
            }
        }
    }

    /// Resolves `relativePath` (as recorded in, e.g., `SourceLocation.filePath`) against this
    /// codebase's directory, rejecting anything that doesn't actually stay inside it.
    ///
    /// This is the one accessor every call site should resolve a codebase-relative path through —
    /// not `codebase.directoryPath` joined inline — so a future change to what backs a codebase's
    /// file access (a shared `GitRepository`/worktree instead of `directoryPath` directly, see
    /// `Codebase.repository`) only has a single call site to update.
    ///
    /// Enforced, not merely trusted: per `USABILITY_GUARDRAILS.md` §5, a path like
    /// `SourceLocation.filePath` can originate from a GitHub-sourced codebase's parsed tree —
    /// external input, not code this app wrote — so an absolute path or a `..`-escape is rejected
    /// rather than silently followed outside the codebase's own directory.
    func resolvedFileURL(relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/") else {
            throw ResolvedFileURLFailure.absolutePath(relativePath)
        }

        let root = URL(fileURLWithPath: directoryPath).resolvingSymlinksInPath()
        let candidate = root.appendingPathComponent(relativePath).resolvingSymlinksInPath()

        let rootPath = root.path
        let candidatePath = candidate.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            throw ResolvedFileURLFailure.pathEscapesCodebaseRoot(relativePath)
        }

        return candidate
    }
}
