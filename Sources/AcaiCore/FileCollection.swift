import Foundation

extension FileManager {
    /// Public so language-target detectors, which live outside AcaiCore, can reuse it.
    ///
    /// `onUnresolvedLink`, when supplied, is called once per entry the walk could not resolve — a
    /// dangling symbolic link, or one outside the caller's security scope — with the path it was
    /// reached by, so a caller that cares (``AnalysisService``, which turns each into a `.skipped`
    /// diagnostic) can report what collection silently dropped before this hook existed.
    ///
    /// A build manifest may name an individual file where a directory is expected (SwiftPM's
    /// `sources:`), so that case is special-cased before the walk: `directory` itself is considered
    /// as the one candidate file, since `DirectoryTreeWalk` only enumerates directory contents.
    public func fileURLs(
        in directory: URL,
        withExtensions extensions: Set<String>,
        excludingDirectories excludedDirectories: Set<String> = AcaiConstants.standard.defaultExcludedSourceDirectories,
        reportingUnresolvedLinks onUnresolvedLink: ((URL) -> Void)? = nil
    ) -> [URL] {
        if (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false {
            guard extensions.contains(directory.pathExtension.lowercased()),
                  !directory.lastPathComponent.hasPrefix(".") else { return [] }
            return [directory]
        }
        var result: [URL] = []
        var walk = DirectoryTreeWalk(excludedDirectories: excludedDirectories, fileManager: self)
        walk.onUnresolvedEntry = onUnresolvedLink
        walk.walk(from: directory) { _, files in
            for file in files where extensions.contains(file.pathExtension.lowercased()) {
                guard !file.lastPathComponent.hasPrefix(".") else { continue }
                result.append(file)
            }
        }
        // The walk yields files in a filesystem-dependent order within each directory. Sort by path
        // so parse order — and therefore the order types appear in generated DOT — is stable across
        // machines, which the golden-file regression tests rely on.
        return result.sorted { $0.path < $1.path }
    }

    /// Which of `extensions` at least one file under `directory` has. Answers "are there sources
    /// here?" without collecting them. Unlike `fileURLs`, this walks the whole subtree regardless of
    /// how early every requested extension is seen: `DirectoryTreeWalk.walk`'s visitor closure has no
    /// way to signal "stop early".
    public func fileExtensionsPresent(
        in directory: URL,
        among extensions: Set<String>,
        excludingDirectories excludedDirectories: Set<String> = AcaiConstants.standard.defaultExcludedSourceDirectories
    ) -> Set<String> {
        guard !extensions.isEmpty else { return [] }
        if (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false {
            let fileExtension = directory.pathExtension.lowercased()
            return extensions.contains(fileExtension) ? [fileExtension] : []
        }
        var found: Set<String> = []
        var walk = DirectoryTreeWalk(excludedDirectories: excludedDirectories, fileManager: self)
        walk.walk(from: directory) { _, files in
            for file in files {
                let fileExtension = file.pathExtension.lowercased()
                if extensions.contains(fileExtension) {
                    found.insert(fileExtension)
                }
            }
        }
        return found
    }
}
