import Foundation

extension FileManager {
    /// Recursively collects files under `directory` whose extension is in `extensions`, skipping
    /// any directory named in `excludedDirectories`. Public so language-target detectors (which now
    /// live outside AcaiCore) can reuse it.
    public func fileURLs(
        in directory: URL,
        withExtensions extensions: Set<String>,
        excludingDirectories excludedDirectories: Set<String> = AcaiConstants.standard.defaultExcludedSourceDirectories
    ) -> [URL] {
        var result: [URL] = []
        guard let enumerator = enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else { return result }

        for case let fileURL as URL in enumerator {
            if let isDir = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir {
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
