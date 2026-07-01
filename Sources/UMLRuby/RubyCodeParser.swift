import UMLCore
import UMLTreeSitter
import TreeSitterRuby

/// Parses Ruby source into a `CodeArtifact` using the tree-sitter Ruby grammar.
public struct RubyCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .ruby
    public let fileExtensions: [String] = ["rb"]

    public init() {}

    public func parse(source: String, fileName: String) -> CodeArtifact {
        let grammar = TreeSitterGrammar(language: Language(language: tree_sitter_ruby()), sourceLanguage: .ruby)
        guard let parser = grammar.makeParser() else {
            return grammar.loadFailureArtifact(fileName: fileName)
        }
        guard let tree = parser.parse(source), let root = tree.rootNode else {
            return CodeArtifact(metadata: .init(sourceLanguage: .ruby, filePaths: [fileName]))
        }
        var extractor = RubyExtractor(source: source, fileName: fileName)
        var artifact = extractor.extract(from: root)
        if root.hasError {
            artifact.metadata.parseDiagnostics = extractor.collectParseDiagnostics(from: root)
        }
        return artifact
    }
}
