import AcaiGit
import Foundation

/// Marks a `Codebase` whose folder the app cloned and owns: a linked worktree of the shared clone
/// of `Codebase.repository.remoteURL`, at `Codebase.repository.ref`. Host-neutral — which service
/// hosts the remote is derived from its URL (`RemoteHost`), never stored.
struct ManagedCheckout: Codable, Hashable {
    /// Disambiguates a branch and a tag sharing `Codebase.repository.ref`'s name.
    var refKind: GitCheckout.Ref.Kind
    var lastSyncedCommitSHA: String?
    var lastSyncedAt: Date?

    init(refKind: GitCheckout.Ref.Kind = .branch, lastSyncedCommitSHA: String? = nil, lastSyncedAt: Date? = nil) {
        self.refKind = refKind
        self.lastSyncedCommitSHA = lastSyncedCommitSHA
        self.lastSyncedAt = lastSyncedAt
    }
}
