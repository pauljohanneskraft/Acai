import Foundation
import UMLCore

/// Detects Swift Package Manager projects (`Package.swift`).
public struct SwiftPackageManagerDetector: BuildSystemDetector {
    public init() {}

    public func isPresent(at root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path)
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        guard requestedLanguages.isEmpty || requestedLanguages.contains(.swift) else { return [] }
        let sourcesDir = root.appendingPathComponent("Sources")
        let dirs: [URL] = FileManager.default.fileExists(atPath: sourcesDir.path) ? [sourcesDir] : [root]
        return [SourceSpec(language: .swift, sourceDirs: dirs)]
    }
}
