import Foundation
import AcaiCore

/// Swift Package Manager takes priority: if both an Xcode project and a `Package.swift`
/// are present, `SwiftPackageManagerDetector` claims Swift first and this detector's
/// Swift spec is suppressed by the coordinator's language-deduplication.
public struct XcodeDetector: BuildSystemDetector {
    public init() {}

    /// A project bundle is not a root of its own, though its embedded `project.xcworkspace` looks like one.
    public func isPresent(at root: URL) -> Bool {
        guard !isProjectBundle(root.lastPathComponent) else { return false }
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return entries.contains(where: isProjectBundle)
    }

    private func isProjectBundle(_ name: String) -> Bool {
        name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace")
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        guard LanguageRequest(requestedLanguages).wants(.swift) else { return [] }
        return [SourceSpec(language: .swift, sourceDirs: [root], root: root)]
    }
}
