import Foundation
import AcaiCore

/// Detects Dart/Flutter projects (`pubspec.yaml`) and locates Dart source files under `lib/`, plus
/// the `bin/` (command-line entry points) and `tool/` directories a package may carry beside it,
/// falling back to the project root if `lib/` doesn't exist.
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

        let sourceDirs = SourceDirectoryProbe(preferring: "lib", alsoIncluding: ["bin", "tool"])
            .directories(in: root)
        guard SourceFilePresence(extensions: ["dart"]).exist(inAnyOf: sourceDirs) else { return [] }
        return [SourceSpec(language: .dart, sourceDirs: sourceDirs, root: root)]
    }
}
