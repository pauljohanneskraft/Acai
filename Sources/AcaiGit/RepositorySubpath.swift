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
    public func offsetting<Value>(_ raw: [String: Value]) -> [String: Value] {
        guard !prefix.isEmpty else { return raw }
        let normalized = normalizedPrefix
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value -> (String, Value)? in
            guard key.hasPrefix(normalized) else { return nil }
            return (String(key.dropFirst(normalized.count)), value)
        })
    }

    /// The inverse: names every key the way git does, so a directory's own paths can be handed to a
    /// repository-wide operation and the result offset straight back.
    public func prefixing<Value>(_ raw: [String: Value]) -> [String: Value] {
        guard !prefix.isEmpty else { return raw }
        let normalized = normalizedPrefix
        return Dictionary(uniqueKeysWithValues: raw.map { (normalized + $0.key, $0.value) })
    }

    private var normalizedPrefix: String {
        prefix.hasSuffix("/") ? prefix : prefix + "/"
    }
}
