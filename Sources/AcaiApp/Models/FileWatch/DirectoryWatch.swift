/// A running watch on one local-folder codebase's directory, started by
/// `FileWatchReindexCoordinator` and stopped either when the codebase is removed or when watching
/// stops making sense for it (e.g. it becomes GitHub-backed). `DirectoryChangeWatcher` (macOS) and
/// `DirectoryPollingWatcher` (iOS) are the two conformances — see `FileWatchReindexCoordinator`'s
/// doc comment for why they differ per platform.
protocol DirectoryWatch: AnyObject {
    func stop()
}
