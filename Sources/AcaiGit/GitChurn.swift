import Foundation
import SwiftGitX

/// Aggregates per-file touch counts across a repository's commit history — the churn half of the
/// classic "hotspot" technique (churn × complexity; Michael Feathers, *Your Code as a Crime
/// Scene*). A real value type over a repository directory (not a namespace): construct one, then
/// ask it to walk.
///
/// Kept independent of `GitRepository`'s shared-clone scheme (`GitRepository.churnByFile`
/// delegates to this) so it also works directly against a plain local git working directory found
/// via `GitRepositoryRoot.find()` — the common case for a transparently-detected local-folder
/// codebase, which is never cloned into `GitRepository`'s shared hub.
public struct GitChurn: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Walks `ref`'s first-parent history, most recent first, up to `limit` commits — mirroring
    /// `GitRepository.commitHistory`'s own walk and its default `limit` (kept modest rather than
    /// generous: `Repository.diff(commit:)` eagerly builds line-level patches for every delta, not
    /// just the changed-file list this method reads, so a much larger window costs real time on a
    /// background task for data never used here).
    ///
    /// Counts each commit that touched a file once, keyed by the file's path (at that commit,
    /// preferring its post-change path so a rename doesn't reset its history) relative to the
    /// repository root. The repository's very first (parentless) commit contributes no touches:
    /// `Repository.diff(commit:)` diffs a parentless commit against itself, which is empty by
    /// construction — an upstream `SwiftGitX` quirk, not something this method special-cases around.
    public func byFile(ref: String, limit: Int = 50) throws -> [String: Int] {
        let repository = try Repository(at: directory, createIfNotExists: false)
        var commit = try GitReference(name: ref).resolve(in: repository)

        var churn: [String: Int] = [:]
        var visited = 0
        while visited < limit {
            let diff = try repository.diff(commit: commit)
            for delta in diff.changes {
                let path = delta.newFile.path.isEmpty ? delta.oldFile.path : delta.newFile.path
                guard !path.isEmpty else { continue }
                churn[path, default: 0] += 1
            }
            visited += 1
            guard let parent = try commit.parents.first else { break }
            commit = parent
        }
        return churn
    }
}
