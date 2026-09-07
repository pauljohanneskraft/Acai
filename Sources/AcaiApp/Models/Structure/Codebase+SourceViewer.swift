import Foundation
#if os(macOS)
import AppKit
#endif

extension Codebase {
    enum SourceResolutionFailure: LocalizedError {
        case fileNotFound(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                String(localized: .app("Error.Codebase.FileNotFound \(path)"))
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
            try resolvedFileURL(relativePath: relativePath, root: root)
        }
    }

    #if os(macOS)
    /// Reveals the file *inside* the access scope: `resolvedFileURL` hands back a URL whose scope
    /// has already been closed, which the sandbox no longer lets Finder be pointed at.
    func revealInFinder(relativePath: String) throws {
        try ScopedResourceAccess(path: directoryPath, bookmark: securityScopedBookmark).withResolvedURL { root in
            let url = try resolvedFileURL(relativePath: relativePath, root: root)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    #endif

    private func resolvedFileURL(relativePath: String, root: URL) throws -> URL {
        let url = try PathEscapeGuard(root: root).resolvedURL(forRelativePath: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SourceResolutionFailure.fileNotFound(relativePath)
        }
        return url
    }
}
