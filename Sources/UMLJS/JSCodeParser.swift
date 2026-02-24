import UMLCore
import UMLTreeSitter
// import TreeSitterJavaScript
import TreeSitterTypeScript

/// Unified parser for both JavaScript and TypeScript (including JSX/TSX).
/// TypeScript is treated as a superset of JavaScript. When `isTypeScript` is true,
/// type annotations, interfaces, type aliases, and enums are parsed.
/// When false, those constructs are skipped/ignored.
public struct JSCodeParser: CodeParser {
    public let isTypeScript: Bool

    public var language: CodeArtifact.SourceLanguage { isTypeScript ? .typeScript : .javaScript }
    public var fileExtensions: [String] { isTypeScript ? ["ts", "tsx"] : ["js", "jsx", "mjs"] }

    /// Creates a parser for JavaScript (`isTypeScript: false`) or TypeScript (`isTypeScript: true`).
    public init(isTypeScript: Bool = true) {
        self.isTypeScript = isTypeScript
    }

    public func parse(source: String, fileName: String) -> CodeArtifact {
        let parser = Parser()
        let lang = Language(language: tree_sitter_typescript())
        try! parser.setLanguage(lang)
        guard let tree = parser.parse(source), let root = tree.rootNode else {
            return CodeArtifact(metadata: .init(sourceLanguage: language, filePaths: [fileName]))
        }
        var extractor = JSExtractor(source: source, fileName: fileName, isTypeScript: isTypeScript)
        return extractor.extract(from: root)
    }
}
