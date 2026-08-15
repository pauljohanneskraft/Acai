import Foundation

/// Trailing-edge debounce: each `trigger()` restarts the delay, and `onFire` runs once, `duration`
/// after the *last* `trigger()` call, only if no further `trigger()` arrived in the meantime. Used
/// by `DirectoryChangeWatcher` to collapse a burst of filesystem events (a save touches several
/// files in quick succession) into a single reindex, and kept as its own type so the debounce
/// timing itself is testable without a real filesystem or `DispatchSource` in the loop.
final class TrailingDebouncer: @unchecked Sendable {
    private let duration: Duration
    private let onFire: @Sendable () -> Void
    private let lock = NSLock()
    private var pendingTask: Task<Void, Never>?

    init(duration: Duration, onFire: @escaping @Sendable () -> Void) {
        self.duration = duration
        self.onFire = onFire
    }

    func trigger() {
        lock.lock()
        defer { lock.unlock() }
        pendingTask?.cancel()
        let duration = duration
        let onFire = onFire
        pendingTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            onFire()
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        pendingTask?.cancel()
        pendingTask = nil
    }
}
