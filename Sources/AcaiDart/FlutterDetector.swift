import Foundation
import AcaiCore

/// Detects Dart/Flutter projects (`pubspec.yaml`) and locates Dart source files.
///
/// Searches for `lib/` (primary source directory in Dart/Flutter projects).
/// Falls back to the project root if `lib/` doesn't exist.
public struct FlutterDetector: BuildSystemDetector {
    public init() {}

    public func isPresent(at root: URL) -> Bool {
        IndicatorFiles(["pubspec.yaml"]).present(at: root)
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        guard LanguageRequest(requestedLanguages).wants(.dart) else { return [] }

        let sourceDirs = SourceDirectoryProbe(preferring: "lib").directories(in: root)
        // Verify that Dart files actually exist.
        guard SourceFilePresence(extensions: ["dart"]).exist(inAnyOf: sourceDirs) else { return [] }
        return [SourceSpec(language: .dart, sourceDirs: sourceDirs)]
    }
}
