import Foundation

/// Every file one analysis can reach, walked once and bucketed by lowercased extension.
///
/// Source collection used to enumerate the tree once per source spec, because each spec asked only
/// for its own language's extensions — nine walks at this repository's root, costing 841 ms. The
/// index walks each distinct source directory once for the whole analysis instead, and a spec
/// narrows the result to its own extensions and source directories afterwards.
///
/// Directories that sit inside another source directory are folded into it, so a file below two of
/// them is still enumerated once. Directories that merely alias each other through a symbolic link
/// are not folded: each keeps its own walk, so a spec reaches its files under the path the detector
/// pointed at rather than under whichever alias was walked first.
struct SourceFileIndex {

    /// One walked source directory: the files below it that some registered language claims, keyed
    /// by extension, plus the entries the walk could not resolve.
    private struct WalkedDirectory {
        let path: String
        let filesByExtension: [String: [URL]]
        let unresolvedLinks: [URL]
    }

    private let walked: [WalkedDirectory]

    /// `extensions` is every registered language's, not one spec's: the walk happens before any spec
    /// is parsed, and keeping only what some language claims is what stops the index holding a whole
    /// checkout's images and archives.
    init(
        sourceDirs: [URL],
        extensions: Set<String>,
        excludingDirectories excludedDirectories: Set<String>,
        enumerationCounter: OperationCounter? = nil
    ) {
        walked = WalkRoots(sourceDirs).paths.map { path in
            let directory = URL(fileURLWithPath: path)
            var filesByExtension: [String: [URL]] = [:]
            var unresolvedLinks: [URL] = []
            let keep = { (file: URL) in
                let fileExtension = file.pathExtension.lowercased()
                guard extensions.contains(fileExtension), !file.lastPathComponent.hasPrefix(".") else { return }
                filesByExtension[fileExtension, default: []].append(file)
            }
            if (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false {
                keep(directory)
            } else {
                var walk = DirectoryTreeWalk(excludedDirectories: excludedDirectories)
                walk.onUnresolvedEntry = { unresolvedLinks.append($0) }
                walk.enumerationCounter = enumerationCounter
                walk.walk(from: directory) { _, files in files.forEach(keep) }
            }
            return WalkedDirectory(
                path: path, filesByExtension: filesByExtension, unresolvedLinks: unresolvedLinks
            )
        }
    }

    /// The files under `directories` carrying one of `extensions`, each directory's own sorted by
    /// path so parse order — and therefore the order types appear in generated DOT — is stable
    /// across machines, which the golden-file regression tests rely on.
    func files(withExtensions extensions: Set<String>, under directories: [URL]) -> [URL] {
        directories.flatMap { directory -> [URL] in
            let path = directory.standardizedFileURL.path
            guard let walk = walked.first(where: { path.isInside($0.path) }) else { return [] }
            return extensions
                .flatMap { walk.filesByExtension[$0] ?? [] }
                .filter { $0.path.isInside(path) }
                .sorted { $0.path < $1.path }
        }
    }

    /// The entries under `directories` the walk could not resolve — a dangling symbolic link, or one
    /// outside the caller's security scope — so a caller can report what collection dropped.
    func unresolvedLinks(under directories: [URL]) -> [URL] {
        directories.flatMap { directory -> [URL] in
            let path = directory.standardizedFileURL.path
            guard let walk = walked.first(where: { path.isInside($0.path) }) else { return [] }
            return walk.unresolvedLinks.filter { $0.path.isInside(path) }
        }
    }
}

/// The source directories worth walking: one entry per directory that does not sit inside another.
///
/// Ancestors are considered first — a containing path is always the shorter one — so a directory is
/// dropped only once the directory that covers it has been kept.
private struct WalkRoots {
    let paths: [String]

    init(_ directories: [URL]) {
        var kept: [String] = []
        for path in directories
            .map(\.standardizedFileURL.path)
            .removingDuplicates()
            .sorted(by: { $0.count < $1.count }) where !kept.contains(where: { path.isInside($0) }) {
            kept.append(path)
        }
        paths = kept
    }
}
