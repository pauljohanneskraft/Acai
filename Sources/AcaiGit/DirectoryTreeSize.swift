import Foundation

/// Recursively sums the allocated on-disk size of every regular file under a directory —
/// `GitRepository.onDiskSize`'s primitive, factored out since it's a plain filesystem concern with
/// nothing git-specific about it.
struct DirectoryTreeSize {
    let directory: URL

    enum Failure: LocalizedError {
        case notADirectory(String)

        var errorDescription: String? {
            switch self {
            case .notADirectory(let path):
                "\"\(path)\" is not a directory."
            }
        }
    }

    /// The total size, in bytes, of every regular file under `directory` (symbolic links are not
    /// followed, so a repository's own object store is counted once even if worktrees link into it).
    func compute() throws -> Int64 {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Failure.notADirectory(directory.path)
        }

        // Deliberately no `.skipsHiddenFiles`: `.git`, the bulk of a repository's actual size, is a
        // hidden directory and must be counted.
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]) else { continue }
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
