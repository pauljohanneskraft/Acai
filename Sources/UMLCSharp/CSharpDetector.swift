import Foundation
import UMLCore

/// Detects C# projects (`.csproj` or `.sln`) and locates C# source files.
public struct CSharpDetector: BuildSystemDetector {
    public init() {}

    public func isPresent(at root: URL) -> Bool {
        IndicatorFiles(suffix: [".csproj", ".sln"]).present(at: root)
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        guard LanguageRequest(requestedLanguages).wants(.cSharp) else { return [] }

        // Standard C# projects typically have sources at the root of the csproj or in specific folders
        let sourceDirs = [root]
        guard SourceFilePresence(extensions: ["cs"]).exist(inAnyOf: sourceDirs) else { return [] }
        return [SourceSpec(language: .cSharp, sourceDirs: sourceDirs)]
    }
}
