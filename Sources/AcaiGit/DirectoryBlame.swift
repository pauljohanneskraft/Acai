import Foundation

/// Blame for files named relative to `directory`, which may sit anywhere inside a git working tree.
public struct DirectoryBlame: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `nil` outside a git working tree; throws `HistoryNotFetched` for a shallow clone. Keys come
    /// back named relative to `directory`, exactly as they went in.
    public func lastTouched(
        inRangesByFile rangesByFile: [String: Set<ClosedRange<Int>>], source: GitBlame.Source
    ) throws -> [String: [ClosedRange<Int>: GitBlame.Line]]? {
        guard let root = GitRepositoryRoot(directory: directory).find() else { return nil }
        let subpath = RepositorySubpath(root: root, directory: directory)
        return subpath.offsetting(
            try GitBlame(directory: root).lastTouched(
                inRangesByFile: subpath.prefixing(rangesByFile), source: source))
    }
}
