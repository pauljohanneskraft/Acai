#if os(macOS)
import Dispatch
import Foundation

/// Not recursive: a directory file descriptor's `DispatchSourceFileSystemObject` reports events for
/// that directory's own entries, not its whole subtree. Acceptable here because every trigger this
/// drives always runs a *full* reindex regardless of which file changed, so this only needs to
/// notice that *something* in the tree moved, and top-level save/build activity reliably touches
/// the root directory's own entries too even when the actual edit was several levels deep.
final class DirectoryChangeWatcher: DirectoryWatch {
    /// A dedicated queue, not `.main`: sharing `.main` would tie event delivery to however busy the
    /// main queue happens to be from unrelated work, which under `swift test --parallel`'s heavy
    /// main-actor contention measurably delayed delivery by several seconds (a real, observed
    /// flake, not a hypothetical).
    private static let eventQueue = DispatchQueue(label: "AcaiApp.DirectoryChangeWatcher", qos: .utility)

    private let fileDescriptor: Int32
    private let source: DispatchSourceFileSystemObject?
    private let debouncer: TrailingDebouncer

    init(directoryPath: String, debounce: Duration = .seconds(3), onChange: @escaping @Sendable () -> Void) {
        debouncer = TrailingDebouncer(duration: debounce, onFire: onChange)
        fileDescriptor = open(directoryPath, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            source = nil
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor, eventMask: [.write, .rename, .delete, .extend], queue: Self.eventQueue)
        source.setEventHandler { [debouncer] in debouncer.trigger() }
        source.setCancelHandler { [fileDescriptor] in close(fileDescriptor) }
        source.resume()
        self.source = source
    }

    func stop() {
        debouncer.cancel()
        source?.cancel()
    }

    deinit {
        stop()
    }
}
#endif
