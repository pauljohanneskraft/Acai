import Foundation

/// A security-scoped bookmark for a directory or file the user granted access to via a system file
/// picker (`.fileImporter`), so that access survives relaunch under App Sandbox rules. Persisted
/// alongside a plain path (`Codebase.securityScopedBookmark`, `QualityCheckConfiguration`) — macOS
/// isn't sandboxed and never mints one, so it stays `nil` there.
struct SecurityScopedBookmark: Codable, Hashable, Sendable {
    var data: Data

    /// Mints a bookmark for `url`. Call this only while `url` is inside an active
    /// `startAccessingSecurityScopedResource()` scope — which a `.fileImporter` completion already is.
    init(resolving url: URL) throws {
        #if os(macOS)
        data = try url.bookmarkData(options: .withSecurityScope)
        #else
        data = try url.bookmarkData(options: .minimalBookmark)
        #endif
    }
}

/// Resolves a stored path/bookmark pair back to a `URL` and brackets filesystem access around a
/// unit of work. On macOS (unsandboxed) this is a thin passthrough to the plain path; on iOS the
/// bookmark is required to regain access to a location picked in an earlier session — without one
/// (e.g. a path entered before bookmarking existed), it falls back to the plain path too, which
/// works only within whatever access the sandbox still happens to grant.
struct ScopedResourceAccess {
    let path: String
    let bookmark: SecurityScopedBookmark?

    enum Failure: LocalizedError {
        case accessDenied(String)

        var errorDescription: String? {
            switch self {
            case .accessDenied(let path):
                "Access to \"\(path)\" was denied. Remove and re-add it to restore access."
            }
        }
    }

    /// Resolves the URL, brackets `startAccessingSecurityScopedResource`/`stop...` around `body` on
    /// iOS, and returns its result. When the stored bookmark has gone stale, mints a fresh one and
    /// hands it to `onRefresh` (still inside the access scope) so the caller can persist it.
    func withResolvedURL<T>(
        onRefresh: ((SecurityScopedBookmark) -> Void)? = nil,
        _ body: (URL) throws -> T
    ) throws -> T {
        #if os(macOS)
        return try body(URL(fileURLWithPath: path).standardizedFileURL)
        #else
        guard let bookmark else {
            return try body(URL(fileURLWithPath: path).standardizedFileURL)
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark.data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard url.startAccessingSecurityScopedResource() else {
            throw Failure.accessDenied(path)
        }
        defer { url.stopAccessingSecurityScopedResource() }
        if isStale, let refreshed = try? SecurityScopedBookmark(resolving: url) {
            onRefresh?(refreshed)
        }
        return try body(url)
        #endif
    }

    /// Holds this resource's security scope open for as long as the instance is alive, for callers
    /// that need continued file access across an extended, non-synchronous span (e.g. handing a URL
    /// to Quick Look, which reads the file lazily while its viewer stays presented) rather than a
    /// single bracketed closure like `withResolvedURL` above. Tied to object lifetime rather than a
    /// `close()` contract a caller could forget to invoke — keep this alive (e.g. as `@State` in the
    /// presenting view) for exactly as long as the resolved URL needs to stay readable, then let it
    /// deinit to release the scope.
    ///
    /// Only meaningful on iOS with a bookmarked (user-picked) local folder: macOS is an unsandboxed
    /// passthrough, and app-managed codebases (e.g. a GitHub clone, which lives inside the app's own
    /// container) never carry a bookmark — both of those cases take the no-op path below.
    @MainActor
    final class LongLivedAccess {
        private var scopedURL: URL?

        init(_ access: ScopedResourceAccess) {
            #if os(iOS)
            guard let bookmark = access.bookmark else { return }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark.data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale
            ), url.startAccessingSecurityScopedResource() else { return }
            scopedURL = url
            #endif
        }

        deinit {
            scopedURL?.stopAccessingSecurityScopedResource()
        }
    }
}
