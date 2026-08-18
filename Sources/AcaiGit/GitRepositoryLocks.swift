import Foundation

/// Serializes every operation routed through one instance: libgit2 doesn't support concurrent
/// writers safely against the same on-disk repository, so a `GitRepository`'s `fetch()`/`sync(ref:)`
/// and any `GitWorktree` add/remove against its shared clone must never run concurrently with each
/// other.
///
/// An actor's own isolation alone is **not** enough for this: actors are reentrant at `await`
/// points, so two calls into a plain `actor` method that itself awaits (as `operation` here always
/// will — a git fetch or checkout) can still interleave instead of running one at a time. This
/// explicitly queues waiters instead, so `run(_:)` provides true mutual exclusion across
/// `operation`'s own suspension points, not just around them.
public actor GitRepositorySerialAccess {
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    @discardableResult
    public func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        if isBusy {
            await withCheckedContinuation { waiters.append($0) }
        }
        isBusy = true
    }

    private func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            isBusy = false
        }
    }
}

/// Vends one shared `GitRepositorySerialAccess` per repository (keyed by its on-disk `localPath`),
/// so every caller touching the same shared clone serializes through the same actor instance
/// instead of racing directly against libgit2. Share one `GitRepositoryLocks` instance for the
/// whole process; a fresh instance provides no exclusion against another fresh instance for the
/// same clone.
public actor GitRepositoryLocks {
    private var locksByPath: [String: GitRepositorySerialAccess] = [:]

    public init() {}

    @discardableResult
    public func run<T: Sendable>(
        for repository: GitRepository, _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        let key = repository.localPath.path
        let access = locksByPath[key] ?? GitRepositorySerialAccess()
        locksByPath[key] = access
        return try await access.run(operation)
    }
}
