import UMLCore
import UMLTreeSitter
import TreeSitterRust

public struct RustCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .rust
    public let fileExtensions: [String] = ["rs"]

    public init() {}

    public func parse(source: String, fileName: String) -> CodeArtifact {
        let grammar = TreeSitterGrammar(language: Language(language: tree_sitter_rust()), sourceLanguage: .rust)
        guard let parser = grammar.makeParser() else {
            return grammar.loadFailureArtifact(fileName: fileName)
        }
        guard let tree = parser.parse(source), let root = tree.rootNode else {
            return CodeArtifact(metadata: .init(sourceLanguage: .rust, filePaths: [fileName]))
        }
        var extractor = RustExtractor(source: source, fileName: fileName)
        var artifact = extractor.extract(from: root)
        if root.hasError {
            artifact.metadata.parseDiagnostics = extractor.collectParseDiagnostics(from: root)
        }
        return artifact
    }
}
