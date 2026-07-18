/// Resolves the `LanguageConfiguration` for an individual type from its own `sourceLanguage`, so a
/// *polyglot* artifact (a base directory mixing e.g. Swift and Python, discovered and enriched
/// per-language but then merged into one `CodeArtifact`) is classified per type at consume time rather
/// than under a single artifact-wide language.
///
/// It carries a **required default** — there is no empty-configuration fallback silently imposed. A
/// type with no stamped language, or a language the backing registry doesn't know, resolves to that
/// default. Agnostic by construction: it is pure data (a registry + a default) and names no language.
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
    /// callers that analysed one language, or by a test fixture — the exact former behaviour of passing
    /// one flat `LanguageConfiguration`.
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
