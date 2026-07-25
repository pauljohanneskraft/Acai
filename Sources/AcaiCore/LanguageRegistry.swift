/// Maps each known `SourceLanguage` to its `LanguageConfiguration`, carrying per-language quirks to
/// downstream stages that only have a `CodeArtifact` and its `metadata.sourceLanguage`. Assembled
/// where the parsers are assembled and injected from there, so agnostic targets never name a language.
///
/// `configuration(for:)` returns `nil` for an unregistered language so a caller can tell "unknown"
/// apart from "known but empty" and choose its own fallback.
public struct LanguageRegistry: Sendable {
    private let configurations: [CodeArtifact.SourceLanguage: LanguageConfiguration]

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
