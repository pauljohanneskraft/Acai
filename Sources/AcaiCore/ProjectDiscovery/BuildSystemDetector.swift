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
    /// Paths under ``sourceDirs`` a build system's manifest declares out of the build. A path is
    /// excluded together with everything below it.
    public var excludedPaths: [URL]
    /// Problems found while discovering this spec — a manifest whose layout could not be read in
    /// full, say, leaving the file set a guess. Merged into the artifact's parse diagnostics, so
    /// ``HealthCheck`` reflects them.
    public var diagnostics: [ParseDiagnostic]
    /// Recorded rather than derived from ``detector``, so no consumer has to recognise a detector's name.
    public var isFallback: Bool

    public init(
        language: CodeArtifact.SourceLanguage,
        sourceDirs: [URL],
        root: URL,
        detector: String = "",
        excludedPaths: [URL] = [],
        diagnostics: [ParseDiagnostic] = [],
        isFallback: Bool = false
    ) {
        self.language = language
        self.sourceDirs = sourceDirs
        self.root = root
        self.detector = detector
        self.excludedPaths = excludedPaths
        self.diagnostics = diagnostics
        self.isFallback = isFallback
    }

    func detected(by detector: any BuildSystemDetector, asFallback: Bool = false) -> SourceSpec {
        var copy = self
        copy.detector = String(describing: type(of: detector))
        copy.isFallback = asFallback
        return copy
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

// MARK: - Detector Claim

/// Everything one detector has to say about one directory: the specs it found, and the languages it
/// deliberately leaves out so the fallback does not add them back.
public struct DetectorClaim {
    public var specs: [SourceSpec]
    public var withheldLanguages: Set<CodeArtifact.SourceLanguage>

    public init(specs: [SourceSpec], withheldLanguages: Set<CodeArtifact.SourceLanguage> = []) {
        self.specs = specs
        self.withheldLanguages = withheldLanguages
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

    /// Languages this root deliberately leaves out, which the fallback must therefore not add back.
    func withheldLanguages(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> Set<CodeArtifact.SourceLanguage>

    /// Both halves of the answer in one call, which is how ``ProjectDiscovery`` asks. A detector that
    /// derives them from the same scan of the directory overrides this to scan once; the default
    /// composes the two separate questions.
    func claim(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> DetectorClaim
}

extension BuildSystemDetector {
    public func withheldLanguages(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> Set<CodeArtifact.SourceLanguage> {
        []
    }

    public func claim(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> DetectorClaim {
        DetectorClaim(
            specs: discoverSourceSpecs(at: root, requestedLanguages: requestedLanguages),
            withheldLanguages: withheldLanguages(at: root, requestedLanguages: requestedLanguages)
        )
    }
}
