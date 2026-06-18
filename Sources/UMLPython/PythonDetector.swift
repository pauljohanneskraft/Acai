import Foundation
import UMLCore

/// Detects Python projects (`pyproject.toml`, `setup.py`, `setup.cfg`, or `requirements.txt`) and
/// locates Python sources.
///
/// Prefers a `src/` layout when present, otherwise searches from the project root.
public struct PythonDetector: BuildSystemDetector {
    private static let manifests = ["pyproject.toml", "setup.py", "setup.cfg", "requirements.txt"]

    public init() {}

    public func isPresent(at root: URL) -> Bool {
        Self.manifests.contains {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        guard requestedLanguages.isEmpty || requestedLanguages.contains(.python) else { return [] }

        let srcDir = root.appendingPathComponent("src")
        let sourceDirs: [URL] = FileManager.default.fileExists(atPath: srcDir.path) ? [srcDir] : [root]

        let hasPython = sourceDirs.contains {
            !FileManager.default.fileURLs(in: $0, withExtensions: ["py"]).isEmpty
        }
        guard hasPython else { return [] }
        return [SourceSpec(language: .python, sourceDirs: sourceDirs)]
    }
}
