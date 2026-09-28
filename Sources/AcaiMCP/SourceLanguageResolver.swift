import MCP
import AcaiLibrary

/// Maps language names (`swift`, `kotlin`, `typescript`, …) onto the engine's `SourceLanguage` constants.
struct SourceLanguageResolver: Sendable {
    private let entries: [(name: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", .swift),
        ("kotlin", .kotlin),
        ("java", .java),
        ("typescript", .typeScript),
        ("javascript", .javaScript),
        ("dart", .dart),
        ("python", .python),
        ("c", .c),
        ("cpp", .cpp)
    ]

    var names: [String] { entries.map(\.name) }

    func language(named name: String) -> CodeArtifact.SourceLanguage? {
        entries.first { $0.name == name.lowercased() }?.language
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
