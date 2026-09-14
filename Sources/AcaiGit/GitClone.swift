import Foundation
import SwiftGitX
import libgit2

/// Clones a remote repository at `ref` into `destination`, or — if already checked out there —
/// incrementally fetches and switches instead. `remoteURL` carries any credentials embedded in its
/// userinfo (e.g. `https://x-access-token:{PAT}@github.com/owner/repo.git`); libgit2's HTTP
/// transport authenticates directly from that, no separate callback needed.
public struct GitClone {
    public let remoteURL: URL
    public let ref: String

    public enum Failure: LocalizedError {
        case libgit2(String)

        public var errorDescription: String? {
            switch self {
            case .libgit2(let message):
                message
            }
        }
    }

    public init(remoteURL: URL, ref: String) {
        self.remoteURL = remoteURL
        self.ref = ref
    }

    /// Clones/syncs `destination` to `ref`'s current commit, replacing its contents (if any) only
    /// once the whole operation has fully succeeded — a failed sync leaves whatever was there
    /// before untouched. Returns the resolved commit's SHA.
    @discardableResult
    public func sync(into destination: URL, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        let repository = try await openOrClone(into: destination, onProgress: onProgress)
        try GitCheckout(directory: destination, repository: repository).switchTo(ref: ref)

        guard let commit = try repository.HEAD.target as? Commit else {
            throw GitReference.Failure.notFound(ref)
        }
        return commit.id.hex
    }

    private func openOrClone(
        into destination: URL, onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> Repository {
        let gitDir = destination.appendingPathComponent(".git")
        if FileManager.default.fileExists(atPath: gitDir.path) {
            let repository: Repository
            do {
                repository = try Repository(at: destination, createIfNotExists: false)
            } catch {
                throw error.asFailure("Couldn't open the repository")
            }
            try await GitCheckout(directory: destination, repository: repository).fetch(onProgress: onProgress)
            return repository
        }

        let workDir = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let scratchClone = workDir.appendingPathComponent("clone", isDirectory: true)

        try rawClone(to: scratchClone, onProgress: onProgress)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: scratchClone, to: destination)

        do {
            return try Repository(at: destination, createIfNotExists: false)
        } catch {
            throw error.asFailure("Couldn't open the cloned repository")
        }
    }

    /// Clones `remoteURL` into `destination` via raw libgit2 C interop, reporting transfer progress
    /// and cooperatively aborting when the calling `Task` is cancelled.
    ///
    /// `SwiftGitX.Repository.clone(from:to:options:transferProgressHandler:)` already wires up a
    /// `git_indexer_progress_cb` and checks `Task.isCancelled` inside it, but returns `1` (a
    /// positive status) to signal cancellation. libgit2's transports only treat a *negative* return
    /// as an abort request (see `git_indexer_progress_cb`'s own contract) — the smart/HTTP
    /// transport used for a real network clone checks the callback's status with `< 0`, so `1`
    /// never stops it and the transfer runs to completion regardless of cancellation. (The local
    /// filesystem transport happens to check `!= 0` instead, which is why this went unnoticed: a
    /// clone from a local fixture, as every existing test here uses, appears to cancel correctly.)
    /// This mirrors `GitFetch`'s already-correct technique instead of depending on that callback.
    private func rawClone(to destination: URL, onProgress: (@Sendable (Double) -> Void)?) throws {
        try Task.checkCancellation()
        do {
            try SwiftGitXRuntime.initialize()
        } catch {
            throw Failure.libgit2("Couldn't initialize libgit2: \(error.message)")
        }
        defer { _ = try? SwiftGitXRuntime.shutdown() }

        var cloneOptions = git_clone_options()
        guard git_clone_options_init(&cloneOptions, UInt32(GIT_CLONE_OPTIONS_VERSION)) == 0 else {
            throw Failure.libgit2(lastErrorMessage("Couldn't initialize clone options"))
        }
        cloneOptions.fetch_opts.callbacks.transfer_progress = { stats, payload in
            guard !Task.isCancelled else { return -1 }
            guard let stats, let payload else { return 0 }
            let handler = payload.assumingMemoryBound(to: CloneProgressHandler.self).pointee
            let total = stats.pointee.total_objects
            guard total > 0 else { return 0 }
            handler(Double(stats.pointee.received_objects) / Double(total))
            return 0
        }

        var handlerPointer: UnsafeMutablePointer<CloneProgressHandler>?
        if let onProgress {
            handlerPointer = .allocate(capacity: 1)
            handlerPointer?.initialize(to: onProgress)
            cloneOptions.fetch_opts.callbacks.payload = UnsafeMutableRawPointer(handlerPointer)
        }
        defer {
            handlerPointer?.deinitialize(count: 1)
            handlerPointer?.deallocate()
        }

        var repositoryPointer: OpaquePointer?
        let status = git_clone(&repositoryPointer, remoteURL.absoluteString, destination.path, &cloneOptions)
        if let repositoryPointer {
            git_repository_free(repositoryPointer)
        }
        guard status == 0 else {
            if status == GIT_EUSER.rawValue || Task.isCancelled {
                throw CancellationError()
            }
            throw Failure.libgit2(lastErrorMessage("Couldn't clone \"\(remoteURL.absoluteString)\""))
        }
    }

    private func lastErrorMessage(_ context: String) -> String {
        if let error = git_error_last(), let message = error.pointee.message {
            return "\(context): \(String(cString: message))"
        }
        return context
    }
}

private typealias CloneProgressHandler = @Sendable (Double) -> Void
