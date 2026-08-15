import Foundation
import SwiftGitX
import libgit2

/// Fetches a repository's `origin` remote via raw libgit2 C interop, reporting transfer progress
/// and cooperatively aborting when the calling `Task` is cancelled.
///
/// `SwiftGitX`'s own `Repository.fetch()` has no options parameter (its own
/// `// TODO: Implement options as parameter`), unlike its
/// `Repository.clone(from:to:options:transferProgressHandler:)`, which already wires
/// `git_indexer_progress_cb` up to a progress handler and checks `Task.isCancelled` inside that
/// callback to abort the transfer. This mirrors that same technique for fetch — and follows
/// `GitWorktree`'s established precedent of opening a raw repository pointer directly when
/// `SwiftGitX`'s wrapper lacks a primitive.
public struct GitFetch {
    public let repositoryDirectory: URL

    public enum Failure: LocalizedError {
        case libgit2(String)

        public var errorDescription: String? {
            switch self {
            case .libgit2(let message):
                message
            }
        }
    }

    public init(repositoryDirectory: URL) {
        self.repositoryDirectory = repositoryDirectory
    }

    /// Fetches the `origin` remote, reporting `received_objects / total_objects` through
    /// `onProgress` as the transfer proceeds. The next time libgit2 calls back into the
    /// transfer-progress hook after the calling `Task` is cancelled, the callback returns a
    /// negative status, which aborts the in-flight transfer (not merely discarding the result) and
    /// surfaces here as `CancellationError`.
    public func run(onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        try Task.checkCancellation()
        let root = GitRepositoryRoot(directory: repositoryDirectory).find() ?? repositoryDirectory
        do {
            try withRepositoryPointer(at: root) { repositoryPointer in
                try fetchOrigin(from: repositoryPointer, onProgress: onProgress)
            }
        } catch is CancellationError {
            throw CancellationError()
        }
    }

    private func fetchOrigin(from repositoryPointer: OpaquePointer, onProgress: (@Sendable (Double) -> Void)?) throws {
        var remotePointer: OpaquePointer?
        guard git_remote_lookup(&remotePointer, repositoryPointer, "origin") == 0, let remotePointer else {
            throw Failure.libgit2(lastErrorMessage("Couldn't find the \"origin\" remote"))
        }
        defer { git_remote_free(remotePointer) }

        var fetchOptions = git_fetch_options()
        guard git_fetch_options_init(&fetchOptions, UInt32(GIT_FETCH_OPTIONS_VERSION)) == 0 else {
            throw Failure.libgit2(lastErrorMessage("Couldn't initialize fetch options"))
        }
        fetchOptions.callbacks.transfer_progress = { stats, payload in
            guard !Task.isCancelled else { return -1 }
            guard let stats, let payload else { return 0 }
            let handler = payload.assumingMemoryBound(to: FetchProgressHandler.self).pointee
            let total = stats.pointee.total_objects
            guard total > 0 else { return 0 }
            handler(Double(stats.pointee.received_objects) / Double(total))
            return 0
        }

        var handlerPointer: UnsafeMutablePointer<FetchProgressHandler>?
        if let onProgress {
            handlerPointer = .allocate(capacity: 1)
            handlerPointer?.initialize(to: onProgress)
            fetchOptions.callbacks.payload = UnsafeMutableRawPointer(handlerPointer)
        }
        defer {
            handlerPointer?.deinitialize(count: 1)
            handlerPointer?.deallocate()
        }

        let status = git_remote_fetch(remotePointer, nil, &fetchOptions, "fetch")
        guard status == 0 else {
            if status == GIT_EUSER.rawValue || Task.isCancelled {
                throw CancellationError()
            }
            throw Failure.libgit2(lastErrorMessage("Couldn't fetch \"origin\""))
        }
    }

    /// Opens `root` as a raw libgit2 handle, runs `body`, and always frees the handle afterward.
    /// Pairs `SwiftGitXRuntime.initialize()`/`.shutdown()` around the raw C calls itself, exactly
    /// like `GitWorktree.withRepositoryPointer` — bypassing `SwiftGitX.Repository` also bypasses the
    /// reference-counted init/shutdown its `init`/`deinit` pair provides.
    private func withRepositoryPointer<T>(at root: URL, _ body: (OpaquePointer) throws -> T) throws -> T {
        do {
            try SwiftGitXRuntime.initialize()
        } catch {
            throw Failure.libgit2("Couldn't initialize libgit2: \(error.message)")
        }
        defer { _ = try? SwiftGitXRuntime.shutdown() }

        var repositoryPointer: OpaquePointer?
        guard git_repository_open(&repositoryPointer, root.path) == 0, let repositoryPointer else {
            throw Failure.libgit2(lastErrorMessage("Couldn't open \"\(root.path)\""))
        }
        defer { git_repository_free(repositoryPointer) }

        return try body(repositoryPointer)
    }

    private func lastErrorMessage(_ context: String) -> String {
        if let error = git_error_last(), let message = error.pointee.message {
            return "\(context): \(String(cString: message))"
        }
        return context
    }
}

private typealias FetchProgressHandler = @Sendable (Double) -> Void
