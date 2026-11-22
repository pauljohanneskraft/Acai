import Foundation

/// One analysis's filesystem reads, so each directory is listed once however many walks cross it.
public final class DirectoryReadCache {
    private let listingCounter: OperationCounter?
    private var listings: [String: [URL]] = [:]
    private var entryNames: [String: Set<String>] = [:]
    private var lastProbed: (path: String, names: Set<String>)?
    private var listedEntries: [String: [DirectoryTreeWalk.Listed]] = [:]
    private var resolvedPaths: [String: URL] = [:]
    private let fileReadCounter: OperationCounter?
    private var fileContents: [String: String?] = [:]

    public init() {
        self.listingCounter = nil
        self.fileReadCounter = nil
    }

    init(listingCounter: OperationCounter?, fileReadCounter: OperationCounter? = nil) {
        self.listingCounter = listingCounter
        self.fileReadCounter = fileReadCounter
    }

    /// The file's UTF-8 contents, or `nil` when it is missing or unreadable, read from disk at most once.
    public func contents(of file: URL) -> String? {
        if let known = fileContents[file.path] { return known }
        var contents: String?
        if hasEntry(named: file.lastPathComponent, in: file.deletingLastPathComponent()) {
            fileReadCounter?.record()
            contents = try? String(contentsOf: file, encoding: .utf8)
        }
        fileContents[file.path] = .some(contents)
        return contents
    }

    /// The directory's entries sorted by name, hidden ones included, under its symlink-resolved path.
    public func entries(of directory: URL) -> [URL] {
        let resolved = resolvedPath(of: directory)
        if let known = listings[resolved.path] { return known }
        listingCounter?.record()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: resolved,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey],
            options: []
        )) ?? []
        let sorted = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
        listings[resolved.path] = sorted
        for entry in sorted {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink == false else { continue }
            let child = resolved.appendingPathComponent(entry.lastPathComponent)
            resolvedPaths[entry.path] = child
            resolvedPaths[child.path] = child
        }
        return sorted
    }

    /// ``entries(of:)`` minus what `FileManager`'s `.skipsHiddenFiles` would leave out.
    public func visibleEntries(of directory: URL) -> [URL] {
        entries(of: directory).filter { entry in
            !entry.lastPathComponent.hasPrefix(".")
                && (try? entry.resourceValues(forKeys: [.isHiddenKey]))?.isHidden != true
        }
    }

    /// Whether `name` exists in `directory`, answering as `FileManager.fileExists` does, case
    /// sensitivity included, while touching the disk only when the listing holds a candidate.
    public func hasEntry(named name: String, in directory: URL) -> Bool {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
            return FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
        }
        guard lowercasedNames(in: directory).contains(name.lowercased()) else { return false }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
    }

    /// Every detector probes the same directory in turn, so the last one asked about is kept at hand.
    private func lowercasedNames(in directory: URL) -> Set<String> {
        let path = directory.path
        if let last = lastProbed, last.path == path { return last.names }
        let resolved = resolvedPath(of: directory)
        let names = entryNames[resolved.path]
            ?? Set(entries(of: resolved).map { $0.lastPathComponent.lowercased() })
        entryNames[resolved.path] = names
        lastProbed = (path, names)
        return names
    }

    func listed(
        at resolvedPath: String, reading read: () -> [DirectoryTreeWalk.Listed]
    ) -> [DirectoryTreeWalk.Listed] {
        if let known = listedEntries[resolvedPath] { return known }
        let entries = read()
        listedEntries[resolvedPath] = entries
        return entries
    }

    func resolvedPath(of url: URL) -> URL {
        if let known = resolvedPaths[url.path] { return known }
        let resolved = url.resolvingSymlinksInPath()
        resolvedPaths[url.path] = resolved
        return resolved
    }
}
