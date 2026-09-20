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
    @discardableResult
    func attachWorktree(
        named worktreeName: String, at worktreeDirectory: URL, depth: GitHistoryDepth = .full,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        let hub = hub
        return try await locks.run(for: hub) {
            try await hub.sync(ref: ref, depth: depth, onProgress: onProgress)
            try GitWorktree(repositoryDirectory: hub.localPath).add(name: worktreeName, at: worktreeDirectory)
            let checkout = try GitCheckout(directory: worktreeDirectory)
            try checkout.switchToDetached(ref: ref)
            return try checkout.headCommitSHA
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
