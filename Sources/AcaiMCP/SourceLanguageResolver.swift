import MCP
import AcaiLibrary

struct SourceLanguageResolver: Sendable {
    private let catalog = LanguageNameCatalog.standard

    var names: [String] { catalog.names }

    func language(named name: String) -> CodeArtifact.SourceLanguage? {
        catalog.language(named: name)
    }

    /// An empty result means "no restriction", as `AnalysisService.analyzeProject` reads it.
    func resolve(names: [String]) -> [CodeArtifact.SourceLanguage] {
        names.compactMap(language(named:))
    }
}

/// The `languages` filter; validated before any parse because the cache only resolves names on a miss.
struct LanguageListArgument: Sendable {
    let name = "languages"
    let description: String
    let resolver = SourceLanguageResolver()

    var property: [String: Value] {
        [
            name: [
                "type": "array",
                "items": ["type": "string", "enum": .array(resolver.names.map(Value.string))],
                "description": .string(description)
            ]
        ]
    }

    func values(in arguments: ToolArguments) throws -> [String] {
        let names = try arguments.stringArray(name)
        for raw in names where resolver.language(named: raw) == nil {
            throw MCPError.invalidParams(
                "Argument '\(name)' must only contain: \(resolver.names.joined(separator: ", ")) (got '\(raw)').")
        }
        return names
    }
}

extension LanguageListArgument {
    static let languages = LanguageListArgument(
        description: "Optional language filter, case-insensitive. Empty means all.")
    static let diffLanguages = LanguageListArgument(
        description: "Optional language filter for directory sides, case-insensitive. Empty means all.")
}
