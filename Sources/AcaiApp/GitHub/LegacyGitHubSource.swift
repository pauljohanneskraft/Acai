import AcaiGit
import Foundation

/// The GitHub-specific shape a managed codebase was persisted in before remotes became
/// host-neutral. Decoded only, to migrate into `ManagedCheckout` + `CodebaseRepositoryReference`;
/// never written. Remove once no persisted data can still carry it.
struct LegacyGitHubSource: Decodable {
    var owner: String
    var repo: String
    var ref: String
    var refKind: GitCheckout.Ref.Kind?
    var lastSyncedCommitSHA: String?
    var lastSyncedAt: Date?

    var managedCheckout: ManagedCheckout {
        ManagedCheckout(
            refKind: refKind ?? .branch, lastSyncedCommitSHA: lastSyncedCommitSHA, lastSyncedAt: lastSyncedAt)
    }
}
