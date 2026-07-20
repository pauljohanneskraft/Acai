import Foundation

/// Walks upward from `directory` to find the git repository it belongs to. `Repository.init(at:)`
/// (via libgit2's `git_repository_open`) requires an exact match on the repository's working
/// directory or its `.git` folder — unlike plain `git`, which searches upward from any
/// subdirectory. This is what lets `GitCheckout`/`GitDiffSnapshot` work when a codebase points at
/// a subdirectory of a larger repository (e.g. one package of a monorepo).
struct GitRepositoryRoot {
    let directory: URL

    /// The nearest ancestor of `directory` (or `directory` itself) containing a `.git` entry, or
    /// `nil` if none is found before reaching the filesystem root.
    func find() -> URL? {
        var candidate = directory.standardizedFileURL
        while true {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent(".git").path) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { return nil }
            candidate = parent
        }
    }
}
