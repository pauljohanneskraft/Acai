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
    func parse(source: String, fileName: String) -> CodeArtifact

    /// This language's quirks (type-name classification, framework stereotypes, generated-code
    /// filtering, build-output directories) consumed by the agnostic pipeline via injection.
    /// Required — every language states its configuration explicitly (a language with no quirks
    /// returns `LanguageConfiguration()` outright rather than inheriting a hidden default).
    var configuration: LanguageConfiguration { get }
}
