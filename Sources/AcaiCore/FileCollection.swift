import Foundation

extension FileManager {
    /// Public so language-target detectors, which live outside AcaiCore, can reuse it.
    ///
    /// `onUnresolvedLink`, when supplied, is called once per entry the walk could not resolve — a
    /// dangling symbolic link, or one outside the caller's security scope — with the path it was
    /// reached by, so a caller that cares (``AnalysisService``, which turns each into a `.skipped`
    /// diagnostic) can report what collection silently dropped before this hook existed.
    public func fileURLs(
        in directory: URL,
        withExtensions extensions: Set<String>,
        excludingDirectories excludedDirectories: Set<String> = AcaiConstants.standard.defaultExcludedSourceDirectories,
        reportingUnresolvedLinks onUnresolvedLink: ((URL) -> Void)? = nil
    ) -> [URL] {
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
}
