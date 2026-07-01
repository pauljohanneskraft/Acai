import UMLCore
import UMLTreeSitter
import TreeSitterCSharp

public struct CSharpCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .cSharp
    public let fileExtensions: [String] = ["cs"]

    public init() {}

    public func parse(source: String, fileName: String) -> CodeArtifact {
        let grammar = TreeSitterGrammar(language: Language(language: tree_sitter_c_sharp()), sourceLanguage: .cSharp)
        guard let parser = grammar.makeParser() else {
            return grammar.loadFailureArtifact(fileName: fileName)
        }
        guard let tree = parser.parse(source), let root = tree.rootNode else {
            return CodeArtifact(metadata: .init(sourceLanguage: .cSharp, filePaths: [fileName]))
        }
        var extractor = CSharpExtractor(source: source, fileName: fileName)
        var artifact = extractor.extract(from: root)
        if root.hasError {
            artifact.metadata.parseDiagnostics = extractor.collectParseDiagnostics(from: root)
        }
        return artifact
    }
}
