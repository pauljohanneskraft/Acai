import AcaiCore
import AcaiTreeSitter
import TreeSitterDart

public struct DartCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .dart
    public let fileExtensions: [String] = ["dart"]

    private let grammar: TreeSitterGrammar

    public init() {
        grammar = TreeSitterGrammar(language: Language(language: tree_sitter_dart()), sourceLanguage: .dart)
    }

    public func parse(source: String, fileName: String) -> CodeArtifact {
        grammar.parse(source: source, fileName: fileName) { root in
            var extractor = DartExtractor(source: source, fileName: fileName, root: root)
            return extractor.extract(from: root)
        }
    }
}
