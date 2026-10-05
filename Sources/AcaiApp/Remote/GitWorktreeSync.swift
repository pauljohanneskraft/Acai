import AcaiGit
import Foundation

/// Ensures a shared, app-managed clone exists for a remote and attaches/moves one codebase's
/// linked worktree against it. Two codebases pointing at the same remote share one on-disk object
/// store and can sit at different commits simultaneously, each in its own worktree.
struct GitWorktreeSync {
    /// May embed credentials (see `RemoteEndpoint.transportURL`). Never persist this; `AcaiGit.GitRepository`
    /// strips credentials before deriving the shared clone's on-disk path, but the caller must still
    /// keep the credential-bearing form out of anything written to `Codebase`/`CodebaseRepositoryReference`.
    let transportURL: URL
    let ref: String
    let hubStoreDirectory: URL
    let locks: GitRepositoryLocks

    var hub: GitRepository {
        GitRepository(remoteURL: transportURL, storeDirectory: hubStoreDirectory)
    }

    /// Syncs the shared hub clone to `ref` (cloning it first if this is the first codebase ever to
    /// reference this remote) and registers a brand-new linked worktree, checked out always
    /// detached. Returns the resolved commit SHA.
    ///
    /// All-or-nothing: cancelling or failing anywhere in here leaves nothing on disk for the
    /// codebase that never came into existence, so a caller handed a `CancellationError` has
    /// nothing to clean up. The cancellation checks bracket the two steps that take real time —
    /// waiting for the hub's lock and the transfer itself — so a clone called off while queued
    /// behind another never starts, and one called off mid-transfer stops at
    /// `GitClone`'s next progress callback.
    @discardableResult
    func attachWorktree(
        named worktreeName: String, at worktreeDirectory: URL, depth: GitHistoryDepth = .full,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        let hub = hub
        return try await locks.run(for: hub) {
            try Task.checkCancellation()
            do {
                try await hub.sync(ref: ref, depth: depth, onProgress: onProgress)
                try Task.checkCancellation()
                try GitWorktree(repositoryDirectory: hub.localPath).add(name: worktreeName, at: worktreeDirectory)
                let checkout = try GitCheckout(directory: worktreeDirectory)
                try checkout.switchToDetached(ref: ref)
                let headSHA = try checkout.headCommitSHA
                try Task.checkCancellation()
                return headSHA
            } catch {
                discardAttachment(named: worktreeName, at: worktreeDirectory)
                throw error
            }
        }
    }

    /// Unwinds a half-finished `attachWorktree`, called while its hub lock is still held. The hub
    /// goes too once no worktree is registered on it, which is the rule `removeWorktree` applies —
    /// a concurrent `attachWorktree` either registered first (and keeps it) or re-clones afterwards.
    private func discardAttachment(named worktreeName: String, at worktreeDirectory: URL) {
        let worktrees = GitWorktree(repositoryDirectory: hub.localPath)
        try? worktrees.remove(name: worktreeName)
        try? FileManager.default.removeItem(at: worktreeDirectory)
        if let remaining = try? worktrees.list(), remaining.isEmpty {
            try? FileManager.default.removeItem(at: hub.localPath)
        }
    }

    /// Moves an **already-registered** worktree at `worktreeDirectory` — used by `pull` (same
    /// `ref`) and `switchRef` (a new one) once a codebase already has a worktree from
    /// `attachWorktree` above.
    @discardableResult
    func resyncWorktree(
        at worktreeDirectory: URL, onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        let hub = hub
        return try await locks.run(for: hub) {
            try await hub.sync(ref: ref, onProgress: onProgress)
            let checkout = try GitCheckout(directory: worktreeDirectory)
            try checkout.switchToDetached(ref: ref)
            return try checkout.headCommitSHA
        }
    }

    /// Deregisters `worktreeName` and deletes its working directory. The shared hub clone goes too
    /// once no worktree is left on it — decided under the hub's lock, so a concurrent
    /// `attachWorktree` either registers first (and keeps it) or re-clones afterwards.
    func removeWorktree(named worktreeName: String) async throws {
        let hub = hub
        try await locks.run(for: hub) {
            let worktrees = GitWorktree(repositoryDirectory: hub.localPath)
            try worktrees.remove(name: worktreeName)
            if try worktrees.list().isEmpty {
                try FileManager.default.removeItem(at: hub.localPath)
            }
        }
    }
}
