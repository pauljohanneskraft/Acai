import Foundation

/// Watches every local-folder codebase's directory (`Codebase.githubSource == nil` — a GitHub-backed
/// codebase is refreshed by `ScheduledRefreshCoordinator` (4d) instead, never by file-watch) and
/// triggers a **full** reindex, debounced, whenever its directory changes. `DirectoryChangeWatcher`
/// on macOS, `DirectoryPollingWatcher` on iOS — see their own doc comments for why they differ per
/// platform.
///
/// `reindex` is injected rather than called directly on a `ProjectCodebaseEditor`: that type is
/// re-created per access (see `ProjectBrowserViewModel.editing`) and isn't something this
/// long-lived coordinator can hold onto, so its owner instead hands in a closure that resolves a
/// fresh editor per call, e.g. `{ [weak self] id in await self?.editing.reindex(codebaseID: id) }`.
/// That existing `reindex(codebaseID:)` already runs through `ActivityCenter`, so a file-watch
/// -triggered reindex shows up in the Activity indicator identically to a manual one, with no
/// separate wiring needed here. Incremental reindexing (only re-parsing changed files) is out of
/// scope and deliberately not what this calls — every trigger is a full `reindex(codebaseID:)`.
@MainActor
final class FileWatchReindexCoordinator {
    private var watchers: [UUID: DirectoryWatch] = [:]
    private let debounce: Duration
    private let reindex: @Sendable (UUID) async -> Void

    init(debounce: Duration = .seconds(3), reindex: @escaping @Sendable (UUID) async -> Void) {
        self.debounce = debounce
        self.reindex = reindex
    }

    /// Reconciles active watchers against `codebases`: starts one for every local-folder codebase
    /// not already watched, stops one for any codebase no longer present or no longer a local
    /// folder. Call whenever the tracked codebase set (or a codebase's `directoryPath`/
    /// `githubSource`) may have changed — e.g. after every `persist()` in `ProjectCodebaseEditor`.
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

    /// Stops every active watcher — e.g. when the owning store is torn down.
    func stopAll() {
        for watcher in watchers.values { watcher.stop() }
        watchers.removeAll()
    }

    private func makeWatcher(directoryPath: String, codebaseID: UUID) -> DirectoryWatch {
        let onChange: @Sendable () -> Void = { [reindex] in
            Task { @MainActor in await reindex(codebaseID) }
        }
        #if os(macOS)
        return DirectoryChangeWatcher(directoryPath: directoryPath, debounce: debounce, onChange: onChange)
        #else
        return DirectoryPollingWatcher(directoryPath: directoryPath, interval: debounce, onChange: onChange)
        #endif
    }
}
