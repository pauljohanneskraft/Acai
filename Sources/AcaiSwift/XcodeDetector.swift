import Foundation
import AcaiCore

/// Detects Xcode projects (`.xcodeproj` / `.xcworkspace`).
///
/// Swift Package Manager takes priority: if both an Xcode project and a `Package.swift`
/// are present, `SwiftPackageManagerDetector` claims Swift first and this detector's
/// Swift spec is suppressed by the coordinator's language-deduplication.
public struct XcodeDetector: BuildSystemDetector {
    public init() {}

    public func isPresent(at root: URL) -> Bool {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return entries.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") })
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        guard LanguageRequest(requestedLanguages).wants(.swift) else { return [] }
        return [SourceSpec(language: .swift, sourceDirs: [root])]
    }
}
