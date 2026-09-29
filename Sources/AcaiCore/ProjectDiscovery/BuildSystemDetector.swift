import Foundation

// MARK: - Source Spec

public struct SourceSpec {
    public var language: CodeArtifact.SourceLanguage
    public var sourceDirs: [URL]
    /// The directory the detector claimed — the folder carrying the indicator file, which is the
    /// project root the source dirs belong to. Not always their parent: a detector may report source
    /// directories from nested modules (Gradle) or the root itself.
    public var root: URL
    /// The claiming detector's type name, stamped by ``ProjectDiscovery`` so a spec can say where it
    /// came from without a detector having to name itself.
    public var detector: String

    public init(
        language: CodeArtifact.SourceLanguage,
        sourceDirs: [URL],
        root: URL,
        detector: String = ""
    ) {
        self.language = language
        self.sourceDirs = sourceDirs
        self.root = root
        self.detector = detector
    }

    func detected(by detector: any BuildSystemDetector) -> SourceSpec {
        var copy = self
        copy.detector = String(describing: type(of: detector))
        return copy
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
