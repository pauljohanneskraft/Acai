import Foundation
import UMLCore

/// Detects Ruby projects (`Gemfile`, `.gemspec`, `.ruby-version`, or `Rakefile`) and locates Ruby
/// source files.
public struct RubyDetector: BuildSystemDetector {
    public init() {}

    public func isPresent(at root: URL) -> Bool {
        IndicatorFiles(["Gemfile", ".ruby-version", "Rakefile"]).present(at: root)
            || hasGemspec(in: root)
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        guard LanguageRequest(requestedLanguages).wants(.ruby) else { return [] }

        let sourceDirs = SourceDirectoryProbe(preferring: "lib").directories(in: root)
        guard SourceFilePresence(extensions: ["rb"]).exist(inAnyOf: sourceDirs) else { return [] }
        return [SourceSpec(language: .ruby, sourceDirs: sourceDirs)]
    }

    private func hasGemspec(in root: URL) -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return false }
        return entries.contains { $0.pathExtension == "gemspec" }
    }
}
