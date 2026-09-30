import Foundation

extension FileManager {
    /// Public so language-target detectors, which live outside AcaiCore, can reuse it.
    public func fileURLs(
        in directory: URL,
        withExtensions extensions: Set<String>,
        excludingDirectories excludedDirectories: Set<String> = AcaiConstants.standard.defaultExcludedSourceDirectories
    ) -> [URL] {
        var result: [URL] = []
        DirectoryTreeWalk(excludedDirectories: excludedDirectories, fileManager: self)
            .walk(from: directory) { _, files in
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
}
