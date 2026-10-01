import Foundation

// MARK: - Source Spec

public struct SourceSpec {
    public var language: CodeArtifact.SourceLanguage
    public var sourceDirs: [URL]

    /// Paths under ``sourceDirs`` a build system's manifest declares out of the build. A path is
    /// excluded together with everything below it.
    public var excludedPaths: [URL]

    /// Problems found while discovering this spec — a manifest whose layout could not be read in
    /// full, say, leaving the file set a guess. Merged into the artifact's parse diagnostics, so
    /// ``HealthCheck`` reflects them.
    public var diagnostics: [ParseDiagnostic]

    public init(
        language: CodeArtifact.SourceLanguage,
        sourceDirs: [URL],
        excludedPaths: [URL] = [],
        diagnostics: [ParseDiagnostic] = []
    ) {
        self.language = language
        self.sourceDirs = sourceDirs
        self.excludedPaths = excludedPaths
        self.diagnostics = diagnostics
    }

    public func excludes(_ file: URL) -> Bool {
        guard !excludedPaths.isEmpty else { return false }
        let path = file.standardizedFileURL.path
        return excludedPaths.contains {
            let excluded = $0.standardizedFileURL.path
            return path == excluded || path.hasPrefix(excluded + "/")
        }
    }
}

// MARK: - Build System Detector Protocol

public protocol BuildSystemDetector: Sendable {
    func isPresent(at root: URL) -> Bool

    /// Filtered to `requestedLanguages`, or all detected languages when the list is empty.
    func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec]
}
