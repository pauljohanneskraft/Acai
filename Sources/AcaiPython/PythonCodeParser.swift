import AcaiCore
import AcaiTreeSitter
import TreeSitterPython

public struct PythonCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .python
    public let fileExtensions: [String] = ["py"]

    private let grammar: TreeSitterGrammar

    public init() {
        grammar = TreeSitterGrammar(language: Language(language: tree_sitter_python()), sourceLanguage: .python)
    }

    public func parse(source: String, fileName: String) -> CodeArtifact {
        grammar.parse(source: source, fileName: fileName) { root in
            var extractor = PythonExtractor(source: source, fileName: fileName, root: root)
            return extractor.extract(from: root)
        }
    }
}
