import AcaiCore
import AcaiTreeSitter
import TreeSitterPython

public struct PythonCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .python
    public let fileExtensions: [String] = ["py"]

    /// Loaded once per run, not per file. The `Parser` stays per-call — it is mutable, and
    /// `CodeParser` is documented stateless between calls.
    private let grammar: TreeSitterGrammar

    public init() {
        grammar = TreeSitterGrammar(language: Language(language: tree_sitter_python()), sourceLanguage: .python)
    }

    public func parse(source: String, fileName: String) -> CodeArtifact {
        guard let parser = grammar.makeParser() else {
            return grammar.loadFailureArtifact(fileName: fileName)
        }
        guard let tree = parser.parse(source), let root = tree.rootNode else {
            return CodeArtifact(metadata: .init(sourceLanguage: .python, filePaths: [fileName]))
        }
        var extractor = PythonExtractor(source: source, fileName: fileName, root: root)
        var artifact = extractor.extract(from: root)
        if root.hasError {
            artifact.metadata.parseDiagnostics = ParseDiagnosticsCollector(
                context: SourceFileContext(source: source, fileName: fileName)
            ).diagnostics(in: root)
        }
        return artifact
    }
}
