import Foundation
import SwiftGitX
import libgit2

/// Manages libgit2 "linked working trees" for one shared `GitRepository`'s clone — the mechanism
/// that lets multiple `Codebase`s check out different refs of the same repository simultaneously
/// without each duplicating its object store. Calls `git_worktree_*` directly: `SwiftGitX` (the
/// higher-level wrapper `AcaiGit` otherwise uses throughout) has no worktree API of its own
/// (confirmed: `SwiftGitXError.worktree` exists only as an error-code case, nothing in `SwiftGitX`
/// calls `git_worktree_*`) — but `libgit2` is already a transitive dependency via `SwiftGitX`, so
/// this is direct C interop, not a new package.
///
/// `git_worktree_add` can only attach a *new* branch (or reuse one at the risk of libgit2's
/// "already checked out" conflict with another worktree) — it has no "detached at an arbitrary
/// commit" option in this libgit2 version. So `add(name:at:)` only creates the worktree (attached
/// to a throwaway branch at the shared clone's current HEAD); callers immediately move it to the
/// ref they actually want via `GitCheckout(directory:).switchToDetached(ref:)` — never
/// `switchTo(ref:)`, which attaches to a branch and would conflict with that same branch already
/// being checked out in the shared clone's own working directory or another worktree.
/// `switchToDetached` reuses `GitCheckout`'s existing, tested branch/tag/SHA resolution instead of
/// duplicating it here in raw C, just always producing a detached HEAD.
public struct GitWorktree {
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

    /// Registers a new linked working tree named `name` at `path`, checked out to a fresh branch
    /// (also named `name`, so it can't collide with a branch a caller cares about) at the shared
    /// repository's current HEAD. `path` must not already exist; its parent is created if needed.
    @discardableResult
    public func add(name: String, at path: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)

        return try withRepositoryPointer { repositoryPointer in
            var addOptions = git_worktree_add_options()
            guard git_worktree_add_options_init(&addOptions, UInt32(GIT_WORKTREE_ADD_OPTIONS_VERSION)) == 0 else {
                throw Failure.libgit2(Self.lastErrorMessage("Couldn't initialize worktree options"))
            }

            var worktreePointer: OpaquePointer?
            let status = git_worktree_add(&worktreePointer, repositoryPointer, name, path.path, &addOptions)
            guard status == 0, let worktreePointer else {
                throw Failure.libgit2(Self.lastErrorMessage("Couldn't add worktree \"\(name)\""))
            }
            git_worktree_free(worktreePointer)

            return path
        }
    }

    /// Names of every linked working tree currently registered for this repository.
    public func list() throws -> [String] {
        try withRepositoryPointer { repositoryPointer in
            var names = git_strarray()
            guard git_worktree_list(&names, repositoryPointer) == 0 else {
                throw Failure.libgit2(Self.lastErrorMessage("Couldn't list worktrees"))
            }
            defer { git_strarray_free(&names) }

            guard let strings = names.strings else { return [] }
            return (0..<names.count).compactMap { index in
                strings[index].map { String(cString: $0) }
            }
        }
    }

    /// Removes the worktree named `name`: prunes libgit2's own bookkeeping
    /// (`.git/worktrees/<name>`) and its working directory. A no-op if nothing is registered under
    /// that name (e.g. it was already removed).
    public func remove(name: String) throws {
        try withRepositoryPointer { repositoryPointer in
            var worktreePointer: OpaquePointer?
            guard git_worktree_lookup(&worktreePointer, repositoryPointer, name) == 0,
                let worktreePointer else {
                return
            }
            defer { git_worktree_free(worktreePointer) }

            var pruneOptions = git_worktree_prune_options()
            guard git_worktree_prune_options_init(&pruneOptions, UInt32(GIT_WORKTREE_PRUNE_OPTIONS_VERSION)) == 0
            else {
                throw Failure.libgit2(Self.lastErrorMessage("Couldn't initialize prune options"))
            }
            pruneOptions.flags = GIT_WORKTREE_PRUNE_VALID.rawValue | GIT_WORKTREE_PRUNE_WORKING_TREE.rawValue

            guard git_worktree_prune(worktreePointer, &pruneOptions) == 0 else {
                throw Failure.libgit2(Self.lastErrorMessage("Couldn't remove worktree \"\(name)\""))
            }
        }
    }

    /// Opens `repositoryDirectory` as a raw libgit2 handle (independent of any `SwiftGitX.Repository`
    /// that might also have it open — worktree operations aren't exposed through that wrapper), runs
    /// `body`, and always frees the handle afterward.
    ///
    /// Bypassing `SwiftGitX.Repository` also bypasses the global libgit2 runtime init/shutdown its
    /// `init`/`deinit` pair, so this pairs the same reference-counted `SwiftGitXRuntime.initialize()`/
    /// `.shutdown()` around the raw C calls itself — otherwise, if no `SwiftGitX.Repository` happens
    /// to be alive at the same moment, libgit2 rejects every call here with "library has not been
    /// initialized".
    private func withRepositoryPointer<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        do {
            try SwiftGitXRuntime.initialize()
        } catch {
            throw Failure.libgit2("Couldn't initialize libgit2: \(error.message)")
        }
        defer { _ = try? SwiftGitXRuntime.shutdown() }

        var repositoryPointer: OpaquePointer?
        guard git_repository_open(&repositoryPointer, repositoryDirectory.path) == 0,
            let repositoryPointer else {
            throw Failure.libgit2(Self.lastErrorMessage("Couldn't open \"\(repositoryDirectory.path)\""))
        }
        defer { git_repository_free(repositoryPointer) }

        return try body(repositoryPointer)
    }

    private static func lastErrorMessage(_ context: String) -> String {
        if let error = git_error_last(), let message = error.pointee.message {
            return "\(context): \(String(cString: message))"
        }
        return context
    }
}
