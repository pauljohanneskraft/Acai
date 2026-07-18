import Foundation
import AcaiCore

/// Detects Swift Package Manager projects (`Package.swift`).
public struct SwiftPackageManagerDetector: BuildSystemDetector {
    public init() {}

    public func isPresent(at root: URL) -> Bool {
        IndicatorFiles(["Package.swift"]).present(at: root)
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        guard LanguageRequest(requestedLanguages).wants(.swift) else { return [] }
        let sourceDirs = SourceDirectoryProbe(preferring: "Sources").directories(in: root)
        return [SourceSpec(language: .swift, sourceDirs: sourceDirs)]
    }
}
