import Foundation

/// Every source directory of one analysis, each walked once through a shared ``DirectoryReadCache``.
struct SourceFileIndex {

    private struct WalkedDirectory {
        let files: [URL]
        let unresolvedLinks: [URL]
    }

    private let walked: [String: WalkedDirectory]

    /// `extensions` is every registered language's, so the index never holds images or archives.
    init(
        sourceDirs: [URL],
        extensions: Set<String>,
        excludingDirectories excludedDirectories: Set<String>,
        reads: DirectoryReadCache
    ) {
        var walked: [String: WalkedDirectory] = [:]
        for directory in sourceDirs where walked[directory.path] == nil {
            var unresolvedLinks: [URL] = []
            let files = SourceDirectoryWalk(
                directory: directory, extensions: extensions, excludedDirectories: excludedDirectories, reads: reads
            ).files { unresolvedLinks.append($0) }
            walked[directory.path] = WalkedDirectory(files: files, unresolvedLinks: unresolvedLinks)
        }
        self.walked = walked
    }

    /// Sorted by path per directory, so parse order (and the generated DOT) is stable across machines.
    func files(withExtensions extensions: Set<String>, under directories: [URL]) -> [URL] {
        directories.flatMap { directory in
            (walked[directory.path]?.files ?? [])
                .filter { extensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.path < $1.path }
        }
    }

    func unresolvedLinks(under directories: [URL]) -> [URL] {
        directories.flatMap { walked[$0.path]?.unresolvedLinks ?? [] }
    }
}

/// A source directory may be a single file a manifest names (SwiftPM's `sources:`), its own candidate.
private struct SourceDirectoryWalk {
    let directory: URL
    let extensions: Set<String>
    let excludedDirectories: Set<String>
    let reads: DirectoryReadCache

    func files(reportingUnresolvedLinks onUnresolvedLink: @escaping (URL) -> Void) -> [URL] {
        if (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false {
            return isCandidate(directory) ? [directory] : []
        }
        var result: [URL] = []
        var walk = DirectoryTreeWalk(excludedDirectories: excludedDirectories)
        walk.onUnresolvedEntry = onUnresolvedLink
        walk.reads = reads
        walk.walk(from: directory) { _, files in
            result.append(contentsOf: files.filter(isCandidate))
        }
        return result
    }

    private func isCandidate(_ file: URL) -> Bool {
        extensions.contains(file.pathExtension.lowercased()) && !file.lastPathComponent.hasPrefix(".")
    }
}
