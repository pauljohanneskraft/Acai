import AcaiGit
import Foundation

/// Ensures a shared, app-managed clone exists for a remote and attaches/moves one codebase's
/// linked worktree against it. Two codebases pointing at the same remote share one on-disk object
/// store and can sit at different commits simultaneously, each in its own worktree.
struct GitWorktreeSync {
    /// May embed credentials (a GitHub PAT in the userinfo). Never persist this; `AcaiGit.GitRepository`
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
        named worktreeName: String, at worktreeDirectory: URL, onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        let hub = hub
        return try await locks.run(for: hub) {
            try await hub.sync(ref: ref, onProgress: onProgress)
            try GitWorktree(repositoryDirectory: hub.localPath).add(name: worktreeName, at: worktreeDirectory)
            let checkout = try GitCheckout(directory: worktreeDirectory)
            try checkout.switchToDetached(ref: ref)
            return try checkout.headCommitSHA
        }
    }

    /// Moves an **already-registered** worktree at `worktreeDirectory` — used by `pull` (same
    /// `ref`) and `switchGitHubRef` (a new one) once a codebase already has a worktree from
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

    /// Deregisters `worktreeName` and deletes its working directory, without touching the shared
    /// hub clone itself — other codebases may still reference it. Removing the hub clone entirely
    /// is a separate, explicit action (the Repositories UI's "Remove" action), gated on no codebase
    /// referencing it any longer.
    func removeWorktree(named worktreeName: String) async throws {
        let hub = hub
        try await locks.run(for: hub) {
            try GitWorktree(repositoryDirectory: hub.localPath).remove(name: worktreeName)
        }
    }
}
