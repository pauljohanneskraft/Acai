import Foundation

// MARK: - Source Spec

public struct SourceSpec {
    public var language: CodeArtifact.SourceLanguage
    public var sourceDirs: [URL]
    /// Problems a detector hit while reading the build system's own manifest. Carried here so a
    /// detector can fall back rather than fail, and still have the reason reach the artifact.
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
