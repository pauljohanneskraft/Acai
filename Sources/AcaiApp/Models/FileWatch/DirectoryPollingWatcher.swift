#if os(iOS)
import Foundation

/// iOS fallback for `DirectoryChangeWatcher`: `DispatchSource.makeFileSystemObjectSource` still
/// works under App Sandbox on iOS, but a security-scoped local-folder codebase's directory handle
/// isn't necessarily kept open the way this needs, and `NSFilePresenter`'s coordinated-file-change
/// API is built around a single well-known document URL rather than an arbitrary externally-picked
/// folder tree — both are a poor fit for "an arbitrary user-picked directory, watched indefinitely
/// in the background" on this platform. Polls the directory's own modification date on `interval`
/// instead: coarser (only catches direct children changing, same as `DirectoryChangeWatcher`'s own
/// non-recursive limitation, and only as often as `interval`) but simple and reliable within the
/// sandbox.
///
/// Runs entirely on a detached background task — filesystem access never happens on the calling
/// (typically main) actor.
final class DirectoryPollingWatcher: DirectoryWatch, @unchecked Sendable {
    private let task: Task<Void, Never>

    init(directoryPath: String, interval: Duration = .seconds(30), onChange: @escaping @Sendable () -> Void) {
        task = Task.detached(priority: .background) {
            var lastModified: Date?
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: directoryPath),
                    let modified = attributes[.modificationDate] as? Date
                else { continue }
                if let lastModified, modified != lastModified {
                    onChange()
                }
                lastModified = modified
            }
        }
    }

    func stop() {
        task.cancel()
    }
}
#endif
