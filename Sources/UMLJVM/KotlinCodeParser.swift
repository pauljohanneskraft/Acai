import UMLCore
import UMLTreeSitter
import TreeSitterKotlin

public struct KotlinCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .kotlin
    public let fileExtensions: [String] = ["kt", "kts"]

    public init() {}

    public func parse(source: String, fileName: String) -> CodeArtifact {
        let grammar = TreeSitterGrammar(language: Language(language: tree_sitter_kotlin()), sourceLanguage: .kotlin)
        guard let parser = grammar.makeParser() else {
            return grammar.loadFailureArtifact(fileName: fileName)
        }
        guard let tree = parser.parse(source), let root = tree.rootNode else {
            return CodeArtifact(metadata: .init(sourceLanguage: .kotlin, filePaths: [fileName]))
        }
        var extractor = KotlinExtractor(source: source, fileName: fileName)
        var artifact = extractor.extract(from: root)
        // Surface concrete ERROR/missing nodes from the best-effort tree so partial output is flagged.
        if root.hasError {
            artifact.metadata.parseDiagnostics = extractor.collectParseDiagnostics(from: root)
        }
        return artifact
    }
}
