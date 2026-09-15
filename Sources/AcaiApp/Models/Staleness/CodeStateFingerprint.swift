import Foundation

enum CodeStateFingerprint: Codable, Hashable, Sendable {
    case git(headCommitSHA: String, isDirty: Bool)
    case fileSystem(latestModification: Date, fileCount: Int, contentDigest: UInt64)
}
