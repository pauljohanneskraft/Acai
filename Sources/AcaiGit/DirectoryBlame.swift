import Foundation

/// Blame for files named relative to `directory`, which may sit anywhere inside a git working tree.
public struct DirectoryBlame: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `nil` outside a git working tree; throws `HistoryNotFetched` for a shallow clone.
    public func lines(_ lines: Set<Int>, inFile path: String) throws -> [Int: GitBlame.Line]? {
        guard let root = GitRepositoryRoot(directory: directory).find() else { return nil }
        let subpath = RepositorySubpath(root: root, directory: directory)
        return try GitBlame(directory: root).lines(lines, inFile: subpath.repositoryPath(path))
    }
}
