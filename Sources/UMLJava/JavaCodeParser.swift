import UMLCore
import UMLTreeSitter
import TreeSitterJava

public struct JavaCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .java
    public let fileExtensions: [String] = ["java"]

    public init() {}

    public func parse(source: String, fileName: String) -> CodeArtifact {
        let parser = Parser()
        let lang = Language(language: tree_sitter_java())
        // swiftlint:disable:next force_try
        try! parser.setLanguage(lang)
        guard let tree = parser.parse(source), let root = tree.rootNode else {
            return CodeArtifact(metadata: .init(sourceLanguage: .java, filePaths: [fileName]))
        }
        var extractor = JavaExtractor(source: source, fileName: fileName)
        return extractor.extract(from: root)
    }
}
