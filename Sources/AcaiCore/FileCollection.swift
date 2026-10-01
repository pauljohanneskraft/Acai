import Foundation

extension FileManager {
    /// Public so language-target detectors, which live outside AcaiCore, can reuse it.
    public func fileURLs(
        in directory: URL,
        withExtensions extensions: Set<String>,
        excludingDirectories excludedDirectories: Set<String> = AcaiConstants.standard.defaultExcludedSourceDirectories
    ) -> [URL] {
        var result: [URL] = []
        walkFiles(in: directory, excludingDirectories: excludedDirectories) { fileURL in
            if extensions.contains(fileURL.pathExtension.lowercased()) {
                result.append(fileURL)
            }
            return true
        }
        // `enumerator` yields files in a filesystem-dependent order. Sort by path so
        // parse order — and therefore the order types appear in generated DOT — is
        // stable across machines, which the golden-file regression tests rely on.
        return result.sorted { $0.path < $1.path }
    }

    /// Which of `extensions` at least one file under `directory` has. Answers "are there sources
    /// here?" without collecting them: the walk stops as soon as every extension has been seen, which
    /// matters because project discovery asks this at every directory it walks.
    public func fileExtensionsPresent(
        in directory: URL,
        among extensions: Set<String>,
        excludingDirectories excludedDirectories: Set<String> = AcaiConstants.standard.defaultExcludedSourceDirectories
    ) -> Set<String> {
        guard !extensions.isEmpty else { return [] }
        var found: Set<String> = []
        walkFiles(in: directory, excludingDirectories: excludedDirectories) { fileURL in
            let fileExtension = fileURL.pathExtension.lowercased()
            if extensions.contains(fileExtension) {
                found.insert(fileExtension)
            }
            return found.count < extensions.count
        }
        return found
    }

    /// Visits every file below `directory`, skipping hidden entries, symlinks (so a cycle can't trap
    /// the walk) and `excludedDirectories` wholesale. `visit` returning `false` ends the walk.
    ///
    /// A build manifest may name an individual file where a directory is expected (SwiftPM's
    /// `sources:`), and an enumerator over a regular file yields nothing — so that case visits the
    /// file itself directly instead of walking.
    private func walkFiles(
        in directory: URL, excludingDirectories excludedDirectories: Set<String>, visit: (URL) -> Bool
    ) {
        if (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false {
            _ = visit(directory)
            return
        }
        guard let enumerator = enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                continue
            }
            if values?.isDirectory == true {
                if excludedDirectories.contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard visit(fileURL) else { return }
        }
    }
}
