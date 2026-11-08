/// Each registered language's lowercased `rawValue`, in registration order, resolved case-insensitively.
public struct LanguageNameCatalog: Sendable {
    public let languages: [CodeArtifact.SourceLanguage]

    public init(parsers: [any CodeParser]) {
        var seen: Set<CodeArtifact.SourceLanguage> = []
        languages = parsers.map(\.language).filter { seen.insert($0).inserted }
    }

    public var names: [String] { languages.map { $0.rawValue.lowercased() } }

    public var namesList: String { names.joined(separator: ", ") }

    public func language(named name: String) -> CodeArtifact.SourceLanguage? {
        let wanted = name.lowercased()
        return languages.first { $0.rawValue.lowercased() == wanted }
    }
}
