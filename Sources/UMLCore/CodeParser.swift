/// A type that can parse source files in a specific language into a `CodeArtifact`.
///
/// Conforming types are value types (structs) that are stateless between calls.
/// Each call to `parse(source:fileName:)` is independent.
public protocol CodeParser: Sendable {
    /// The source language this parser handles.
    var language: CodeArtifact.SourceLanguage { get }

    /// Lowercase file extensions (without the dot) for source files of this language.
    /// e.g. `["kt", "kts"]` for Kotlin.
    var fileExtensions: [String] { get }

    /// Parse a single source file and return its type model.
    ///
    /// **Producer contract** (the implicit invariants enrichment and rendering depend on — enforced by
    /// the parser-conformance suite, issue #89, and centralised in ``TypeIdentityResolver``):
    /// - Each ``TypeDeclaration`` has ``TypeDeclaration/id`` == ``TypeDeclaration/qualifiedName``
    ///   (namespace-qualified), while ``TypeDeclaration/name`` is the **simple** name.
    /// - A nested type's id/qualified name is **hierarchically prefixed** by its parent's.
    /// - ``Relationship`` and supertype endpoints are names the resolver can map to a declared id, or
    ///   legitimately-external names (carried through as-is).
    /// - ``TypeReference/name`` and ``CallSite/receiverType`` are **simple** names (primitive/collection
    ///   classification and call-site resolution match by exact simple name).
    /// - ``TypeDeclaration/extensionOf`` matches a target's qualified name / id / name after generics
    ///   are stripped.
    func parse(source: String, fileName: String) -> CodeArtifact

    /// This language's quirks (type-name classification, framework stereotypes, generated-code
    /// filtering, build-output directories) consumed by the agnostic pipeline via injection.
    /// Required — every language states its configuration explicitly (a language with no quirks
    /// returns `LanguageConfiguration()` outright rather than inheriting a hidden default).
    var configuration: LanguageConfiguration { get }
}
