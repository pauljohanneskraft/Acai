import Foundation

/// A security-scoped bookmark for a directory or file the user granted access to via a system file
/// picker (`.fileImporter`), so that access survives relaunch under App Sandbox rules. Both the
/// macOS and the iOS app are sandboxed.
struct SecurityScopedBookmark: Codable, Hashable, Sendable {
    var data: Data

    /// Call this only while `url` is inside an active `startAccessingSecurityScopedResource()`
    /// scope — which a `.fileImporter` completion already is.
    init(resolving url: URL) throws {
        #if os(macOS)
        data = try url.bookmarkData(options: .withSecurityScope)
        #else
        data = try url.bookmarkData(options: .minimalBookmark)
        #endif
    }
}

/// Re-establishes access to a location picked in an earlier session. Without a bookmark (an
/// app-managed directory, or a codebase added before bookmarking existed) it falls back to the
/// plain path, which works only within whatever access the sandbox still happens to grant — a
/// picker grant from the current session, or a location inside the app's own container.
struct ScopedResourceAccess {
    let path: String
    let bookmark: SecurityScopedBookmark?

    /// What `onRefresh` hands back for the caller to persist: the bookmark resolved to a location
    /// that no longer matches `path` (the folder was moved or renamed), so both need updating.
    struct Refreshed: Sendable {
        var bookmark: SecurityScopedBookmark
        var url: URL
    }

    enum Failure: LocalizedError, Equatable {
        case accessDenied(String)
        case directoryUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .accessDenied(let path):
                String(localized: .app("Error.ScopedResourceAccess.AccessDenied \(path)"))
            case .directoryUnavailable(let path):
                String(localized: .app("Error.ScopedResourceAccess.DirectoryUnavailable \(path)"))
            }
        }
    }

    /// Mints a fresh bookmark and hands it to `onRefresh` (still inside the access scope) when the
    /// stored one has gone stale or resolved to a different location than `path`.
    func withResolvedURL<T>(
        onRefresh: ((Refreshed) -> Void)? = nil,
        _ body: (URL) throws -> T
    ) throws -> T {
        if let scoped = try? resolvedScopedURL() {
            defer { scoped.url.stopAccessingSecurityScopedResource() }
            try probe(scoped.url)
            let moved = scoped.url.path != URL(fileURLWithPath: path).standardizedFileURL.path
            if scoped.isStale || moved, let refreshed = try? SecurityScopedBookmark(resolving: scoped.url) {
                onRefresh?(Refreshed(bookmark: refreshed, url: scoped.url))
            }
            return try body(scoped.url)
        }
        // No bookmark, or one that no longer resolves: the plain path still works while the
        // sandbox grants access some other way (a picker grant from this session, or the app's
        // own container), so try it before giving up.
        let plain = URL(fileURLWithPath: path).standardizedFileURL
        try probe(plain)
        return try body(plain)
    }

    /// A resolved bookmark whose security scope is open — the caller owns balancing it with
    /// `stopAccessingSecurityScopedResource()`.
    private struct Scoped {
        var url: URL
        var isStale: Bool
    }

    /// A `nil` bookmark and a failed `startAccessingSecurityScopedResource()` are the same answer
    /// to the caller: no scoped URL, fall back to the plain path.
    private func resolvedScopedURL() throws -> Scoped {
        guard let bookmark else { throw Failure.accessDenied(path) }
        var isStale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        let url = try URL(
            resolvingBookmarkData: bookmark.data,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard url.startAccessingSecurityScopedResource() else { throw Failure.accessDenied(path) }
        return Scoped(url: url, isStale: isStale)
    }

    /// `FileManager.fileURLs`' `enumerator(at:)` answers a denial by handing back an enumerator
    /// that yields nothing, so the denial reaches `AnalysisService` as an empty file list and
    /// surfaces as "no source files could be parsed". `contentsOfDirectory` throws instead, which
    /// is the whole point of probing before handing the URL on.
    private func probe(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw Failure.directoryUnavailable(path)
        }
        guard isDirectory.boolValue else { return }
        do {
            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        } catch {
            throw Failure.accessDenied(path)
        }
    }

    /// Holds this resource's security scope open for as long as the instance is alive, for callers
    /// that need continued file access across an extended, non-synchronous span (e.g. handing a URL
    /// to Quick Look) rather than a single bracketed closure like `withResolvedURL` above. Tied to
    /// object lifetime rather than a `close()` contract a caller could forget to invoke — keep this
    /// alive (e.g. as `@State` in the presenting view) for as long as the URL needs to stay readable.
    ///
    /// A no-op for an app-managed directory, which has no bookmark and needs no scope.
    @MainActor
    final class LongLivedAccess {
        private var scopedURL: URL?

        /// `nil` when the scope couldn't be opened — the caller keeps whatever access it already
        /// had rather than treating this as a failure.
        var url: URL? { scopedURL }

        init(_ access: ScopedResourceAccess) {
            scopedURL = (try? access.resolvedScopedURL())?.url
        }

        deinit {
            scopedURL?.stopAccessingSecurityScopedResource()
        }
    }
}
