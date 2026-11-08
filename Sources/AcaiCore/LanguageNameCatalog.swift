/// The tool-facing names of a parser set — each registered language's `rawValue` lowercased, in
/// registration order — resolved case-insensitively.
///
/// Derived from the parsers themselves rather than written out, so registering a parser is the only
/// step needed to make its language reachable from every surface that names languages (the CLI's
/// `--language`, the MCP server's `languages` filter and its JSON-schema enum). Agnostic: it reads
/// `CodeParser.language` and names no language of its own.
public struct LanguageNameCatalog: Sendable {
    public let languages: [CodeArtifact.SourceLanguage]

    public init(parsers: [any CodeParser]) {
        var seen: Set<CodeArtifact.SourceLanguage> = []
        languages = parsers.map(\.language).filter { seen.insert($0).inserted }
    }

    public var names: [String] { languages.map { $0.rawValue.lowercased() } }

    /// For help text and error messages: `swift, kotlin, java, …`.
    public var namesList: String { names.joined(separator: ", ") }

    public func language(named name: String) -> CodeArtifact.SourceLanguage? {
        let wanted = name.lowercased()
        return languages.first { $0.rawValue.lowercased() == wanted }
    }
}
