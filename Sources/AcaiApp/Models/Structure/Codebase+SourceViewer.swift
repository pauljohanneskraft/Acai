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

    /// The one accessor every call site should resolve a codebase-relative path through, rather
    /// than inlining `directoryPath` + path-joining directly, so a future change to what backs file
    /// access only needs updating here.
    ///
    /// Runs synchronously — callers on a `View`/view model should dispatch this off the main actor
    /// (e.g. `Task.detached`), since it touches the filesystem.
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
