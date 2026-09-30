import Foundation

/// Every directory under a root, in a deterministic order, **following symbolic links**.
///
/// Links are followed because a workspace that symlinks a shared package into place would otherwise
/// lose it entirely — no warning, just fewer types than the codebase has. A directory is entered at
/// most once per walk, keyed on its symlink-resolved path, so a link pointing at an ancestor
/// terminates instead of looping, and a link aliasing a directory the walk already covered
/// contributes its files once rather than twice.
///
/// Subdirectories are visited in sorted order, so which of two aliasing paths a file is reported
/// under does not depend on the order the filesystem happens to list them in.
struct DirectoryTreeWalk: Sendable {

    private enum Entry {
        case directory
        case file
        case missing
    }

    let excludedDirectories: Set<String>
    var fileManager: FileManager = .default

    /// Calls `body` once per directory with that directory's files. Hidden entries are listed —
    /// `.gitignore` is one — but a hidden directory is never descended into, matching the source
    /// collection this shares a tree with.
    func walk(from root: URL, visiting body: (_ directory: URL, _ files: [URL]) -> Void) {
        var visited: Set<String> = []
        var stack = [root]
        while let current = stack.popLast() {
            guard visited.insert(current.resolvingSymlinksInPath().path).inserted else { continue }
            var directories: [URL] = []
            var files: [URL] = []
            for entry in sortedContents(of: current) {
                switch kind(of: entry) {
                case .directory where isDescendable(entry): directories.append(entry)
                case .file: files.append(entry)
                case .directory, .missing: continue
                }
            }
            body(current, files)
            stack.append(contentsOf: directories.reversed())
        }
    }

    private func isDescendable(_ directory: URL) -> Bool {
        let name = directory.lastPathComponent
        return !name.hasPrefix(".") && !excludedDirectories.contains(name)
    }

    private func sortedContents(of directory: URL) -> [URL] {
        let contents = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []
        )
        return (contents ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// A symbolic link is classified by what it resolves to, so a link to a directory is descended
    /// into and a link that dangles is dropped rather than parsed as an empty file.
    private func kind(of url: URL) -> Entry {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard let values else { return .missing }
        guard values.isSymbolicLink != true else { return resolvedKind(of: url) }
        return values.isDirectory == true ? .directory : .file
    }

    private func resolvedKind(of url: URL) -> Entry {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return .missing }
        return isDirectory.boolValue ? .directory : .file
    }
}
