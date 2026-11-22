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
struct DirectoryTreeWalk {

    enum Entry {
        case directory
        case file
        case missing
    }

    /// A directory entry under both the path the walk reached it by and the path it actually lives
    /// at. The two differ as soon as a link is involved, and both are needed: the real one to list
    /// and to stat, the logical one so a file keeps the path the caller pointed at.
    private struct Child {
        let logical: URL
        let real: URL
    }

    /// One listed entry, classified and resolved once however many walks reach its directory.
    struct Listed {
        let name: String
        let kind: Entry
        let resolved: URL
        let resolvedPath: String
        let pathExtension: String
    }

    let excludedDirectories: Set<String>
    var fileManager: FileManager = .default

    /// Called once per entry the walk could not resolve — a dangling link, a link out of the
    /// caller's security scope, or a stat failure — with the path the walk reached it by. `nil`
    /// (the default) keeps the old silent drop for callers that don't need to report it (the
    /// `.gitignore` walk, which already has its own diagnostics for malformed rules).
    var onUnresolvedEntry: ((URL) -> Void)?

    /// Shares filesystem reads with other walks of the same analysis; `nil` reads afresh.
    var reads: DirectoryReadCache?

    /// Calls `body` once per directory with that directory's files. Hidden entries are listed —
    /// `.gitignore` is one — but a hidden directory is never descended into, matching the source
    /// collection this shares a tree with. Stops early once the current task is cancelled.
    ///
    /// A file is reported under the first (sorted) directory path the walk reaches it by. Two
    /// paths that alias the same file on disk — a symlink sitting next to the file it links to,
    /// or two links to the same target — contribute it once, keyed on its symlink-resolved path,
    /// matching the guarantee already made for aliased directories.
    func walk(
        from root: URL,
        until isDone: () -> Bool = { false },
        visiting body: (_ directory: URL, _ files: [URL]) -> Void
    ) {
        walkListed(from: root, until: isDone) { directory, files in
            body(directory, files.map { directory.appendingPathComponent($0.name, isDirectory: false) })
        }
    }

    /// ``walk(from:until:visiting:)`` handing over each file's listing rather than a URL built for it.
    func walkListed(
        from root: URL,
        until isDone: () -> Bool = { false },
        visiting body: (_ directory: URL, _ files: [Listed]) -> Void
    ) {
        var visitedDirectories: Set<String> = []
        var visitedFiles: Set<String> = []
        var stack = [Child(logical: root, real: resolvedPath(of: root))]
        while !Task.isCancelled, !isDone(), let current = stack.popLast() {
            let realPath = current.real.path
            guard visitedDirectories.insert(realPath).inserted else { continue }
            var directories: [Child] = []
            var files: [Listed] = []
            for listed in listedEntries(at: current.real, path: realPath) {
                switch listed.kind {
                case .directory where isDescendable(listed.name):
                    directories.append(Child(
                        logical: current.logical.appendingPathComponent(listed.name, isDirectory: true),
                        real: listed.resolved
                    ))
                case .file where visitedFiles.insert(listed.resolvedPath).inserted:
                    files.append(listed)
                case .file, .directory:
                    continue
                case .missing:
                    onUnresolvedEntry?(current.logical.appendingPathComponent(listed.name))
                }
            }
            body(current.logical, files)
            stack.append(contentsOf: directories.reversed())
        }
    }

    private func listedEntries(at resolvedDirectory: URL, path: String) -> [Listed] {
        guard let reads else { return listing(at: resolvedDirectory) }
        return reads.listed(at: path) { listing(at: resolvedDirectory) }
    }

    private func listing(at resolvedDirectory: URL) -> [Listed] {
        sortedEntries(at: resolvedDirectory).map { entry in
            let kind = kind(of: entry)
            let resolved = kind == .missing ? entry : resolved(entry, in: resolvedDirectory)
            return Listed(
                name: entry.lastPathComponent, kind: kind, resolved: resolved, resolvedPath: resolved.path,
                pathExtension: kind == .file ? entry.pathExtension.lowercased() : ""
            )
        }
    }

    /// Only a link needs resolving: anything else sits at its resolved parent's path plus its name.
    private func resolved(_ entry: URL, in resolvedParent: URL) -> URL {
        let values = try? entry.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values?.isSymbolicLink == false else { return resolvedPath(of: entry) }
        return resolvedParent.appendingPathComponent(entry.lastPathComponent)
    }

    private func isDescendable(_ name: String) -> Bool {
        !name.hasPrefix(".") && !excludedDirectories.contains(name)
    }

    /// Listing goes through the resolved path: handed a symlinked directory, `contentsOfDirectory`
    /// reports it as empty rather than as an error, which is how a linked-in source directory used
    /// to disappear without a diagnostic. Each child is then re-expressed under the path the walk
    /// arrived by, so the link's own spelling — and therefore every relative path derived from it —
    /// survives.
    private func sortedEntries(at resolved: URL) -> [URL] {
        reads.map { $0.entries(of: resolved) } ?? listing(of: resolved)
    }

    private func listing(of resolved: URL) -> [URL] {
        let contents = try? fileManager.contentsOfDirectory(
            at: resolved,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        return (contents ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func resolvedPath(of url: URL) -> URL {
        reads.map { $0.resolvedPath(of: url) } ?? url.resolvingSymlinksInPath()
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
