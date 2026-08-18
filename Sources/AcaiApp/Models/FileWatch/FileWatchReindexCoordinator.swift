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
    private var watchers: [UUID: DirectoryWatch] = [:]
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
            uniqueKeysWithValues: codebases.filter { $0.githubSource == nil }.map { ($0.id, $0.directoryPath) })

        for (id, watcher) in watchers where localFolders[id] == nil {
            watcher.stop()
            watchers.removeValue(forKey: id)
        }
        for (id, path) in localFolders where watchers[id] == nil {
            watchers[id] = makeWatcher(directoryPath: path, codebaseID: id)
        }
    }

    func stopAll() {
        for watcher in watchers.values { watcher.stop() }
        watchers.removeAll()
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
