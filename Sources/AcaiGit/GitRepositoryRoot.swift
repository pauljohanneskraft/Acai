import Foundation

/// Walks upward from `directory` to find the git repository it belongs to. `Repository.init(at:)`
/// requires an exact match on the working directory or `.git` folder — unlike plain `git`, which
/// searches upward from any subdirectory.
///
/// Public: `AcaiApp`'s local-folder codebase picker (`NewCodebaseSheet`) reuses this exact walk to
/// detect when a user-picked folder is already a git working directory (or a subdirectory of one),
/// so it can offer to add it as a repository-backed `Codebase` instead of a plain local folder.
public struct GitRepositoryRoot {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Walks upward using `NSString.deletingLastPathComponent` rather than
    /// `URL.deletingLastPathComponent()` — the latter never converges at `/` on Darwin (it keeps
    /// prepending `..` indefinitely), which would spin this loop forever for any non-git directory.
    public func find() -> URL? {
        var candidate = directory.standardizedFileURL.path
        while true {
            if FileManager.default.fileExists(atPath: candidate + "/.git") {
                return URL(fileURLWithPath: candidate)
            }
            guard candidate != "/" else { return nil }
            candidate = (candidate as NSString).deletingLastPathComponent
        }
    }
}
