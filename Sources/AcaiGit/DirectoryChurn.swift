import Foundation

/// Per-file churn keyed relative to `directory`, which may sit anywhere inside a git working tree.
public struct DirectoryChurn: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `nil` outside a git working tree; throws `HistoryNotFetched` for a shallow clone.
    public func byFile(ref: String = "HEAD", limit: Int = 50) throws -> [String: Int]? {
        guard let root = GitRepositoryRoot(directory: directory).find() else { return nil }
        let raw = try GitChurn(directory: root).byFile(ref: ref, limit: limit)
        return RepositorySubpath(root: root, directory: directory).offsetting(raw)
    }
}
