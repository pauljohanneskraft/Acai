import Foundation

/// A directory's path below its repository root (`""` for the root itself). Translates between the
/// repository-relative paths git reports and the directory-relative paths a codebase names.
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
        let normalized = normalizedPrefix
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value -> (String, Int)? in
            guard key.hasPrefix(normalized) else { return nil }
            return (String(key.dropFirst(normalized.count)), value)
        })
    }

    /// The inverse of `offsetting(_:)` for a single path: what git calls a file the directory knows
    /// as `path`.
    public func repositoryPath(_ path: String) -> String {
        guard !prefix.isEmpty else { return path }
        return normalizedPrefix + path
    }

    private var normalizedPrefix: String {
        prefix.hasSuffix("/") ? prefix : prefix + "/"
    }
}
