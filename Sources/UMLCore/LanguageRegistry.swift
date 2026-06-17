/// Maps each known `SourceLanguage` to its `LanguageConfiguration`.
///
/// This is the value that carries per-language quirks to the downstream stages (diagram
/// enrichment, rendering, export) which only have a `CodeArtifact` and its `metadata.sourceLanguage`.
/// It is assembled where the parsers are assembled (the composition root / `AnalysisService`) and
/// injected from there, so the agnostic targets never name a language themselves.
///
/// `configuration(for:)` returns `nil` for an unregistered language so a caller can tell "unknown"
/// apart from "known but empty" and choose its own fallback rather than have one silently imposed.
public struct LanguageRegistry: Sendable {
    private let configurations: [CodeArtifact.SourceLanguage: LanguageConfiguration]

    public init(_ configurations: [CodeArtifact.SourceLanguage: LanguageConfiguration] = [:]) {
        self.configurations = configurations
    }

    /// Builds a registry from a parser set, taking each parser's `configuration`.
    public init(parsers: [any CodeParser]) {
        var configurations: [CodeArtifact.SourceLanguage: LanguageConfiguration] = [:]
        for parser in parsers {
            configurations[parser.language] = parser.configuration
        }
        self.configurations = configurations
    }

    /// The configuration registered for `language`, or `nil` when none is registered.
    public func configuration(for language: CodeArtifact.SourceLanguage) -> LanguageConfiguration? {
        configurations[language]
    }

    /// The union of every registered language's build-output directories.
    public var excludedDirectories: Set<String> {
        configurations.values.reduce(into: Set<String>()) { $0.formUnion($1.excludedDirectories) }
    }
}
