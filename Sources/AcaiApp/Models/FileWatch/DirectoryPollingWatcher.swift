#if os(iOS)
import Foundation

/// `DispatchSource.makeFileSystemObjectSource` and `NSFilePresenter` are both a poor fit for "an
/// arbitrary user-picked directory, watched indefinitely in the background" under iOS's App
/// Sandbox, so this polls the directory's own modification date on `interval` instead: coarser
/// (only catches direct children changing, and only as often as `interval`) but simple and
/// reliable within the sandbox.
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
