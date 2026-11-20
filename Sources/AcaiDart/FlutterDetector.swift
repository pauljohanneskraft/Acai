import Foundation
import AcaiCore

/// Detects Dart/Flutter projects (`pubspec.yaml`) and locates Dart source files under `lib/`,
/// falling back to the project root if `lib/` doesn't exist.
public struct FlutterDetector: BuildSystemDetector {
    public init() {}

    public func isPresent(at root: URL) -> Bool {
        IndicatorFiles(["pubspec.yaml"]).present(at: root)
    }

    public func isPresent(at root: URL, reading reads: DirectoryReadCache) -> Bool {
        IndicatorFiles(["pubspec.yaml"]).present(at: root, reading: reads)
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        claim(at: root, requestedLanguages: requestedLanguages, reading: DirectoryReadCache()).specs
    }

    public func claim(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage],
        reading reads: DirectoryReadCache
    ) -> DetectorClaim {
        guard LanguageRequest(requestedLanguages).wants(.dart) else { return DetectorClaim(specs: []) }

        let sourceDirs = SourceDirectoryProbe(preferring: "lib").directories(in: root, reading: reads)
        guard SourceFilePresence(extensions: ["dart"]).exist(inAnyOf: sourceDirs, reading: reads) else {
            return DetectorClaim(specs: [])
        }
        return DetectorClaim(specs: [SourceSpec(language: .dart, sourceDirs: sourceDirs, root: root)])
    }
}
