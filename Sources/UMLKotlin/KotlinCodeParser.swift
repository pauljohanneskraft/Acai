import UMLCore
import UMLTreeSitter
import TreeSitterKotlin

public struct KotlinCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .kotlin
    public let fileExtensions: [String] = ["kt", "kts"]

    public init() {}

    public func parse(source: String, fileName: String) -> CodeArtifact {
        let parser = Parser()
        let lang = Language(language: tree_sitter_kotlin())
        // swiftlint:disable:next force_try
        try! parser.setLanguage(lang)
        guard let tree = parser.parse(source), let root = tree.rootNode else {
            return CodeArtifact(metadata: .init(sourceLanguage: .kotlin, filePaths: [fileName]))
        }
        let extractor = KotlinExtractor(source: source, fileName: fileName)
        return extractor.extract(from: root)
    }
}
