import Foundation
import UMLCore

/// Detects Dart/Flutter projects (`pubspec.yaml`) and locates Dart source files.
///
/// Searches for `lib/` (primary source directory in Dart/Flutter projects).
/// Falls back to the project root if `lib/` doesn't exist.
public struct FlutterDetector: BuildSystemDetector {
    public init() {}

    public func isPresent(at root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent("pubspec.yaml").path)
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        guard requestedLanguages.isEmpty || requestedLanguages.contains(.dart) else { return [] }

        let libDir = root.appendingPathComponent("lib")
        let sourceDirs: [URL]

        if FileManager.default.fileExists(atPath: libDir.path) {
            sourceDirs = [libDir]
        } else {
            sourceDirs = [root]
        }

        // Verify that Dart files actually exist.
        let hasDart = sourceDirs.contains {
            !FileManager.default.fileURLs(in: $0, withExtensions: ["dart"]).isEmpty
        }

        guard hasDart else { return [] }
        return [SourceSpec(language: .dart, sourceDirs: sourceDirs)]
    }
}
