import UMLCore
import UMLTreeSitter
import TreeSitterDart

public struct DartCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .dart
    public let fileExtensions: [String] = ["dart"]

    public init() {}

    public func parse(source: String, fileName: String) -> CodeArtifact {
        let parser = Parser()
        let lang = Language(language: tree_sitter_dart())
        // swiftlint:disable:next force_try
        try! parser.setLanguage(lang)
        guard let tree = parser.parse(source), let root = tree.rootNode else {
            return CodeArtifact(metadata: .init(sourceLanguage: .dart, filePaths: [fileName]))
        }
        var extractor = DartExtractor(source: source, fileName: fileName)
        var artifact = extractor.extract(from: root)
        // Tree-sitter always returns a best-effort tree; flag ERROR/missing nodes so partial output is surfaced.
        artifact.metadata.hasParseErrors = root.hasError
        return artifact
    }
}
