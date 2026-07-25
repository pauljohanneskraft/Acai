import Foundation

/// Walks upward from `directory` to find the git repository it belongs to. `Repository.init(at:)`
/// requires an exact match on the working directory or `.git` folder — unlike plain `git`, which
/// searches upward from any subdirectory.
struct GitRepositoryRoot {
    let directory: URL

    /// The nearest ancestor of `directory` (or `directory` itself) containing a `.git` entry, or
    /// `nil` if none is found before reaching the filesystem root.
    ///
    /// Walks upward using `NSString.deletingLastPathComponent` rather than
    /// `URL.deletingLastPathComponent()` — the latter never converges at `/` on Darwin (it keeps
    /// prepending `..` indefinitely), which would spin this loop forever for any non-git directory.
    func find() -> URL? {
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
