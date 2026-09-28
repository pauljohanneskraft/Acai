import Foundation
import AcaiCore

public struct SwiftPackageManagerDetector: BuildSystemDetector {
    private let manifestName = "Package.swift"

    public init() {}

    public func isPresent(at root: URL) -> Bool {
        IndicatorFiles([manifestName]).present(at: root)
    }

    /// Reads the manifest's declared target layout where it can, and probes the filesystem where it
    /// can't — recording why, since a probed layout may parse files the package excludes or miss a
    /// target that lives outside `Sources/`.
    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        guard LanguageRequest(requestedLanguages).wants(.swift) else { return [] }
        guard let source = try? String(contentsOf: root.appendingPathComponent(manifestName), encoding: .utf8)
        else {
            return [probedSpec(at: root, reason: "the manifest could not be read")]
        }
        let sources = SwiftPackageSources(root: root, manifest: SwiftPackageManifest(source: source))
        guard let resolved = sources.resolved else {
            return [probedSpec(at: root, reason: sources.fallbackReason ?? "the manifest could not be read")]
        }
        return [SourceSpec(
            language: .swift, sourceDirs: resolved.sourceDirs, excludedPaths: resolved.excludedPaths
        )]
    }

    private func probedSpec(at root: URL, reason: String) -> SourceSpec {
        SourceSpec(
            language: .swift,
            sourceDirs: SourceDirectoryProbe(preferring: "Sources").directories(in: root),
            diagnostics: [ParseDiagnostic(
                location: SourceLocation(filePath: manifestName, line: 1, column: 1),
                kind: .incompleteDiscovery,
                message: "\(manifestName) was not used to find sources: \(reason). "
                    + "Source directories were guessed from the folder layout instead."
            )]
        )
    }
}
