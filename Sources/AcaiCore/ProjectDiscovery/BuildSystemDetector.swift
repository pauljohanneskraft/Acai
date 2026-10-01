import Foundation

// MARK: - Source Spec

public struct SourceSpec {
    public var language: CodeArtifact.SourceLanguage
    public var sourceDirs: [URL]

    /// Problems found while discovering this spec — a manifest whose layout could not be read in
    /// full, say, leaving the file set a guess. Merged into the artifact's parse diagnostics, so
    /// ``HealthCheck`` reflects them.
    public var diagnostics: [ParseDiagnostic]

    public init(
        language: CodeArtifact.SourceLanguage,
        sourceDirs: [URL],
        diagnostics: [ParseDiagnostic] = []
    ) {
        self.language = language
        self.sourceDirs = sourceDirs
        self.diagnostics = diagnostics
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
