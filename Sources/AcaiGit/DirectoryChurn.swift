import Foundation

/// Per-file churn for a directory that may sit anywhere inside a git working tree — the source
/// root of an analysis, which is often a subdirectory of the repository (a monorepo package) and
/// sometimes not in a repository at all.
///
/// Resolves the repository root upward from `directory`, walks its history through `GitChurn`, and
/// offsets the repository-root-relative paths that come back down to `directory`-relative ones,
/// so the keys line up with the `SourceLocation.filePath` an analysis records.
public struct DirectoryChurn: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `nil` when `directory` is not inside a git working tree at all — distinct from an empty (but
    /// non-`nil`) map, which means a real repository with no history to report. Throws
    /// `HistoryNotFetched` for a shallow clone, whose churn would count only the commits that
    /// happen to have been fetched.
    public func byFile(ref: String = "HEAD", limit: Int = 50) throws -> [String: Int]? {
        guard let root = GitRepositoryRoot(directory: directory).find() else { return nil }
        let raw = try GitChurn(directory: root).byFile(ref: ref, limit: limit)
        return RepositorySubpath(root: root, directory: directory).offsetting(raw)
    }
}

/// One directory's path relative to the repository root it lives under — `""` when the directory
/// *is* the root — and the re-keying that turns repository-root-relative paths into paths relative
/// to that subdirectory.
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

    /// Strips `prefix` off every key, dropping the entries that fall outside it. A pass-through
    /// when the prefix is empty.
    public func offsetting(_ raw: [String: Int]) -> [String: Int] {
        guard !prefix.isEmpty else { return raw }
        let normalized = prefix.hasSuffix("/") ? prefix : prefix + "/"
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value -> (String, Int)? in
            guard key.hasPrefix(normalized) else { return nil }
            return (String(key.dropFirst(normalized.count)), value)
        })
    }
}
