import Foundation

/// Computes a ``CodeStateFingerprint/fileSystem(latestModification:fileCount:contentDigest:)`` over
/// a source tree: the newest modification time, a file count, and an order-independent digest
/// folding each file's `(relativePath, mtime, size)` — the digest is what catches a rename/move or
/// content swap alone, which preserve mtime and count. ``directory`` may itself be a single file (a
/// stored `.json` baseline), fingerprinted as one entry.
public struct SourceTreeFingerprint: Sendable {
    public let directory: URL

    private static let skippedDirectories: Set<String> = [
        ".build", ".git", ".swiftpm", "node_modules", "DerivedData", "build",
        ".gradle", "dist", "Pods", "__pycache__", ".venv", "venv"
    ]

    public init(directory: URL) {
        self.directory = directory
    }

    public func compute() -> CodeStateFingerprint {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        if let values = try? directory.resourceValues(forKeys: keys), values.isRegularFile == true {
            let modified = values.contentModificationDate ?? .distantPast
            let size = values.fileSize ?? 0
            let digest = FileFingerprint(
                relativePath: directory.lastPathComponent, modified: modified, size: size).stableHash
            return .fileSystem(latestModification: modified, fileCount: 1, contentDigest: digest)
        }

        let rootPath = directory.standardizedFileURL.path
        var latest = Date.distantPast
        var count = 0
        var digest: UInt64 = 0
        let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isDirectory == true {
                if Self.skippedDirectories.contains(url.lastPathComponent) {
                    enumerator?.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            count += 1
            let modified = values?.contentModificationDate ?? .distantPast
            if modified > latest { latest = modified }
            let relativePath = String(url.standardizedFileURL.path.dropFirst(rootPath.count))
            let size = values?.fileSize ?? 0
            digest &+= FileFingerprint(relativePath: relativePath, modified: modified, size: size).stableHash
        }
        return .fileSystem(latestModification: latest, fileCount: count, contentDigest: digest)
    }
}

private struct FileFingerprint {
    let relativePath: String
    let modified: Date
    let size: Int

    /// FNV-1a hash, seed-free so it's deterministic across the process's lifetime.
    var stableHash: UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(relativePath)|\(modified.timeIntervalSinceReferenceDate.bitPattern)|\(size)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
