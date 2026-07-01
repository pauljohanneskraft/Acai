import Foundation
import UMLCore

/// Detects Cargo projects (`Cargo.toml`) and locates Rust source files.
///
/// Prefers `src/` when present, otherwise searches from the project root.
public struct CargoDetector: BuildSystemDetector {
    public init() {}

    public func isPresent(at root: URL) -> Bool {
        IndicatorFiles(["Cargo.toml"]).present(at: root)
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        guard LanguageRequest(requestedLanguages).wants(.rust) else { return [] }

        let sourceDirs = SourceDirectoryProbe(preferring: "src").directories(in: root)
        let presence = SourceFilePresence(
            extensions: ["rs"],
            excludingDirectories: RustCodeParser().configuration.excludedDirectories
        )
        guard presence.exist(inAnyOf: sourceDirs) else { return [] }
        return [SourceSpec(language: .rust, sourceDirs: sourceDirs)]
    }
}
