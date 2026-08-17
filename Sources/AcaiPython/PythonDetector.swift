import Foundation
import AcaiCore

/// `IndicatorFiles`/`SourceDirectoryProbe`/`SourceFilePresence` are constructed where used rather
/// than stored — holding a `SourceFilePresence` as a stored property currently mis-compiles.
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
