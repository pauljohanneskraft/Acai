import Foundation
import AcaiCore

/// Detects Python projects (`pyproject.toml`, `setup.py`, `setup.cfg`, or `requirements.txt`) and
/// locates Python sources.
///
/// Prefers a `src/` layout when present, otherwise searches from the project root.
///
/// The reusable detector components (`IndicatorFiles`, `SourceDirectoryProbe`, `SourceFilePresence`)
/// are constructed where they're used rather than held as stored properties — they are cheap value
/// types, and holding a `SourceFilePresence` as a stored property currently mis-compiles.
public struct PythonDetector: BuildSystemDetector {
    public init() {}

    public func isPresent(at root: URL) -> Bool {
        IndicatorFiles(["pyproject.toml", "setup.py", "setup.cfg", "requirements.txt"]).present(at: root)
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        guard LanguageRequest(requestedLanguages).wants(.python) else { return [] }

        let sourceDirs = SourceDirectoryProbe(preferring: "src").directories(in: root)
        guard SourceFilePresence(extensions: ["py"]).exist(inAnyOf: sourceDirs) else { return [] }
        return [SourceSpec(language: .python, sourceDirs: sourceDirs)]
    }
}
