import AcaiCore
import AcaiTreeSitter
import TreeSitterKotlin

public struct KotlinCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .kotlin
    public let fileExtensions: [String] = ["kt", "kts"]

    private let grammar: TreeSitterGrammar

    public init() {
        grammar = TreeSitterGrammar(language: Language(language: tree_sitter_kotlin()), sourceLanguage: .kotlin)
    }

    public func parse(source: String, fileName: String) -> CodeArtifact {
        grammar.parse(source: source, fileName: fileName) { root in
            var extractor = KotlinExtractor(source: source, fileName: fileName, root: root)
            return extractor.extract(from: root)
        }
    }
}
