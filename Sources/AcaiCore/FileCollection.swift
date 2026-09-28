import Foundation

extension FileManager {
    /// Public so language-target detectors, which live outside AcaiCore, can reuse it.
    public func fileURLs(
        in directory: URL,
        withExtensions extensions: Set<String>,
        excludingDirectories excludedDirectories: Set<String> = AcaiConstants.standard.defaultExcludedSourceDirectories
    ) -> [URL] {
        var result: [URL] = []
        // A build manifest may name an individual file where a directory is expected (SwiftPM's
        // `sources:`), and an enumerator over a regular file yields nothing.
        if (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false {
            return extensions.contains(directory.pathExtension.lowercased()) ? [directory] : []
        }
        guard let enumerator = enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else { return result }

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
            if extensions.contains(fileURL.pathExtension.lowercased()) {
                result.append(fileURL)
            }
        }
        // `enumerator` yields files in a filesystem-dependent order. Sort by path so
        // parse order — and therefore the order types appear in generated DOT — is
        // stable across machines, which the golden-file regression tests rely on.
        return result.sorted { $0.path < $1.path }
    }
}
