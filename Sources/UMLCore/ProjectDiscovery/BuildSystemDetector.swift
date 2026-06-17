import Foundation

// MARK: - Source Spec

/// A language paired with the directories that contain its source files.
public struct SourceSpec {
    public var language: CodeArtifact.SourceLanguage
    public var sourceDirs: [URL]

    public init(language: CodeArtifact.SourceLanguage, sourceDirs: [URL]) {
        self.language = language
        self.sourceDirs = sourceDirs
    }
}

// MARK: - Build System Detector Protocol

/// A type that knows how to detect a specific build system and locate its source files.
public protocol BuildSystemDetector: Sendable {
    /// Returns `true` if this build system is present at the given project root.
    func isPresent(at root: URL) -> Bool

    /// Returns source specs for this build system, filtered to `requestedLanguages`
    /// (or all detected languages when the list is empty).
    func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec]
}
