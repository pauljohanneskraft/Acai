import Foundation

extension Codebase {
    enum SourceResolutionFailure: LocalizedError {
        case fileNotFound(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                "\"\(path)\" could not be found in this codebase."
            }
        }
    }

    /// Resolves a codebase-relative path (as stored in `SourceLocation.filePath`) to a real file
    /// `URL`, validating it against path-escape/symlink-escape attacks (`PathEscapeGuard`, per
    /// `USABILITY_GUARDRAILS.md` §5) and confirming the file actually exists. This is the one
    /// accessor every call site should resolve a codebase-relative path through, rather than
    /// inlining `directoryPath` + path-joining directly — a future change to what backs a
    /// codebase's file access (see `BACKLOG.md` B02, which moves `Codebase` onto a `Repository`
    /// reference) only has this one call site to update instead of several scattered ones.
    ///
    /// Runs synchronously — callers on a `View`/view model should dispatch this off the main actor
    /// (e.g. `Task.detached`) per `USABILITY_GUARDRAILS.md` §1, since it touches the filesystem.
    func resolvedFileURL(relativePath: String) throws -> URL {
        try ScopedResourceAccess(path: directoryPath, bookmark: securityScopedBookmark).withResolvedURL { root in
            let url = try PathEscapeGuard(root: root).resolvedURL(forRelativePath: relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SourceResolutionFailure.fileNotFound(relativePath)
            }
            return url
        }
    }
}
