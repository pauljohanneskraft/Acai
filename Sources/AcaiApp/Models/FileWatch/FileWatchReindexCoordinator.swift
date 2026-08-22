import Foundation

/// Watches every local-folder codebase's directory (`Codebase.githubSource == nil`; a GitHub-backed
/// codebase is refreshed by `ScheduledRefreshCoordinator` instead) and triggers a **full** reindex,
/// debounced, whenever its directory changes.
///
/// `reindex` is injected rather than called directly on a `ProjectCodebaseEditor`: that type is
/// re-created per access and isn't something this long-lived coordinator can hold onto, so its
/// owner instead hands in a closure that resolves a fresh editor per call. Incremental reindexing
/// (only re-parsing changed files) is out of scope — every trigger is a full `reindex(codebaseID:)`.
@MainActor
final class FileWatchReindexCoordinator {
    /// The watcher opens the directory directly (`open(_:O_EVTONLY)`), which the sandbox refuses
    /// unless the codebase's security scope is held open for as long as the watch lasts — hence
    /// the `access` alongside it.
    private struct Watch {
        var watcher: DirectoryWatch
        var access: ScopedResourceAccess.LongLivedAccess
        var key: Key
    }

    /// A watch survives a `sync` only while it still points at the same location: a relocated or
    /// re-bookmarked codebase needs its scope and file descriptor re-opened.
    private struct Key: Equatable {
        var path: String
        var bookmark: SecurityScopedBookmark?
    }

    private var watchers: [UUID: Watch] = [:]
    private let debounce: Duration
    private let didFinishDebounceWindow: (@Sendable () -> Void)?
    private let reindex: @Sendable (UUID) async -> Void

    /// - Parameter didFinishDebounceWindow: fires once per debounce window elapsing, after the
    ///   resulting `reindex` call completes — a settle signal for tests that need to distinguish
    ///   "correctly didn't reindex" from "hasn't finished yet."
    init(
        debounce: Duration = .seconds(3),
        didFinishDebounceWindow: (@Sendable () -> Void)? = nil,
        reindex: @escaping @Sendable (UUID) async -> Void
    ) {
        self.debounce = debounce
        self.didFinishDebounceWindow = didFinishDebounceWindow
        self.reindex = reindex
    }

    /// Call whenever the tracked codebase set (or a codebase's `directoryPath`/`githubSource`) may
    /// have changed.
    func sync(codebases: [Codebase]) {
        let localFolders = Dictionary(
            uniqueKeysWithValues: codebases.filter { $0.githubSource == nil }
                .map { ($0.id, Key(path: $0.directoryPath, bookmark: $0.securityScopedBookmark)) })

        for (id, watch) in watchers where localFolders[id] != watch.key {
            watch.watcher.stop()
            watchers.removeValue(forKey: id)
        }
        for (id, key) in localFolders where watchers[id] == nil {
            watchers[id] = makeWatch(key: key, codebaseID: id)
        }
    }

    func stopAll() {
        for watch in watchers.values { watch.watcher.stop() }
        watchers.removeAll()
    }

    private func makeWatch(key: Key, codebaseID: UUID) -> Watch {
        let access = ScopedResourceAccess.LongLivedAccess(
            ScopedResourceAccess(path: key.path, bookmark: key.bookmark))
        // The bookmark may resolve the folder somewhere else entirely (it was moved); the open
        // scope covers that URL, not the stored path.
        let watcher = makeWatcher(directoryPath: access.url?.path ?? key.path, codebaseID: codebaseID)
        return Watch(watcher: watcher, access: access, key: key)
    }

    private func makeWatcher(directoryPath: String, codebaseID: UUID) -> DirectoryWatch {
        let onChange: @Sendable () -> Void = { [reindex, didFinishDebounceWindow] in
            Task { @MainActor in
                await reindex(codebaseID)
                didFinishDebounceWindow?()
            }
        }
        #if os(macOS)
        return DirectoryChangeWatcher(directoryPath: directoryPath, debounce: debounce, onChange: onChange)
        #else
        return DirectoryPollingWatcher(directoryPath: directoryPath, interval: debounce, onChange: onChange)
        #endif
    }
}
