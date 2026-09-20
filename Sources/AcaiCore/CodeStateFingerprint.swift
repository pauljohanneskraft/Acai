import Foundation

/// A cheap proxy for "has this source tree changed since it was last analyzed" — either a git
/// checkout's head commit and dirty flag (cheap and precise when the source is a checkout), or a
/// digest over the tree's files (the fallback for anything else, including a single stored `.json`
/// baseline).
public enum CodeStateFingerprint: Codable, Hashable, Sendable {
    case git(headCommitSHA: String, isDirty: Bool)
    case fileSystem(latestModification: Date, fileCount: Int, contentDigest: UInt64)
}
