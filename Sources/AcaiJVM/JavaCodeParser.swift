import AcaiCore
import AcaiTreeSitter
import TreeSitterJava

public struct JavaCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .java
    public let fileExtensions: [String] = ["java"]

    private let grammar: TreeSitterGrammar

    public init() {
        grammar = TreeSitterGrammar(language: Language(language: tree_sitter_java()), sourceLanguage: .java)
    }

    public func parse(source: String, fileName: String) -> CodeArtifact {
        grammar.parse(source: source, fileName: fileName) { root in
            var extractor = JavaExtractor(source: source, fileName: fileName, root: root)
            return extractor.extract(from: root)
        }
    }
}
