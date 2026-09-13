import Foundation

/// A snapshot of a codebase's on-disk state, captured when it was last indexed and compared against
/// the current state to say whether the analysis still matches the code. Persisted on `Codebase`.
enum CodeStateFingerprint: Codable, Hashable, Sendable {
    /// The checkout's resolved `HEAD` commit and whether the working tree had uncommitted changes —
    /// used when the codebase sits inside a git repository.
    case git(headCommitSHA: String, isDirty: Bool)
    /// Every regular file's latest modification time, file count, and an order-independent content
    /// digest — used when there's no repository to consult instead, so a plain folder is covered too.
    case fileSystem(latestModification: Date, fileCount: Int, contentDigest: UInt64)
}
