/// Resolves the `LanguageConfiguration` for an individual type from its own `sourceLanguage`, so a
/// polyglot artifact is classified per type rather than under a single artifact-wide language.
///
/// Carries a required default — no empty-configuration fallback is silently imposed. A type with no
/// stamped language, or a language the backing registry doesn't know, resolves to that default.
public struct LanguageConfigurationResolver: Sendable {
    private let registry: LanguageRegistry
    /// The configuration used for a type whose language is unknown to `registry` (or unstamped).
    public let defaultConfiguration: LanguageConfiguration

    /// A per-language resolver backed by `registry`, falling back to `defaultConfiguration` for a
    /// language the registry doesn't know.
    public init(registry: LanguageRegistry, default defaultConfiguration: LanguageConfiguration) {
        self.registry = registry
        self.defaultConfiguration = defaultConfiguration
    }

    /// The single-language shortcut: a resolver that returns `configuration` for every type. Used by
    /// callers that analysed one language, or by a test fixture.
    public init(single configuration: LanguageConfiguration) {
        self.init(registry: LanguageRegistry(parsers: []), default: configuration)
    }

    /// The configuration for `language`, or the default when the registry doesn't know it.
    public func configuration(for language: CodeArtifact.SourceLanguage) -> LanguageConfiguration {
        registry.configuration(for: language) ?? defaultConfiguration
    }

    /// The configuration for `type`, resolved from its stamped `sourceLanguage`; the default when the
    /// type is unstamped (e.g. a synthesised external placeholder).
    public func configuration(for type: TypeDeclaration) -> LanguageConfiguration {
        guard let language = type.sourceLanguage else { return defaultConfiguration }
        return configuration(for: language)
    }
}
