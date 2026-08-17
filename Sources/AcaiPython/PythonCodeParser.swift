import AcaiCore
import AcaiTreeSitter
import TreeSitterPython

public struct PythonCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .python
    public let fileExtensions: [String] = ["py"]

    public init() {}

    public func parse(source: String, fileName: String) -> CodeArtifact {
        let grammar = TreeSitterGrammar(language: Language(language: tree_sitter_python()), sourceLanguage: .python)
        guard let parser = grammar.makeParser() else {
            return grammar.loadFailureArtifact(fileName: fileName)
        }
        guard let tree = parser.parse(source), let root = tree.rootNode else {
            return CodeArtifact(metadata: .init(sourceLanguage: .python, filePaths: [fileName]))
        }
        var extractor = PythonExtractor(source: source, fileName: fileName)
        var artifact = extractor.extract(from: root)
        if root.hasError {
            artifact.metadata.parseDiagnostics = extractor.collectParseDiagnostics(from: root)
        }
        return artifact
    }
}
