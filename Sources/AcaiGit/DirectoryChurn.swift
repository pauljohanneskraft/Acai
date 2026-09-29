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

/// A directory's path below its repository root (`""` for the root itself).
public struct RepositorySubpath: Sendable {
    public let prefix: String

    public init(prefix: String) {
        self.prefix = prefix
    }

    public init(root: URL, directory: URL) {
        let rootPath = root.standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        guard directoryPath != rootPath, directoryPath.hasPrefix(rootPath + "/") else {
            self.init(prefix: "")
            return
        }
        self.init(prefix: String(directoryPath.dropFirst(rootPath.count + 1)))
    }

    /// Strips `prefix` off every key, dropping the entries outside it.
    public func offsetting(_ raw: [String: Int]) -> [String: Int] {
        guard !prefix.isEmpty else { return raw }
        let normalized = prefix.hasSuffix("/") ? prefix : prefix + "/"
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value -> (String, Int)? in
            guard key.hasPrefix(normalized) else { return nil }
            return (String(key.dropFirst(normalized.count)), value)
        })
    }
}
