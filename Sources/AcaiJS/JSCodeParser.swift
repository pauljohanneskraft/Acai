import AcaiCore
import AcaiTreeSitter
import TreeSitterTypeScript

/// Unified parser for both JavaScript and TypeScript (including JSX/TSX). When `isTypeScript` is
/// true, type annotations, interfaces, type aliases, and enums are parsed; when false those
/// constructs are skipped.
public struct JSCodeParser: CodeParser {
    public let isTypeScript: Bool

    public var language: CodeArtifact.SourceLanguage { grammar.sourceLanguage }
    public var fileExtensions: [String] { isTypeScript ? ["ts", "tsx"] : ["js", "jsx", "mjs"] }

    /// The TypeScript grammar parses plain JavaScript too, so both dialects share it.
    private let grammar: TreeSitterGrammar

    public init(isTypeScript: Bool = true) {
        self.isTypeScript = isTypeScript
        grammar = TreeSitterGrammar(
            language: Language(language: tree_sitter_typescript()),
            sourceLanguage: isTypeScript ? .typeScript : .javaScript
        )
    }

    public func parse(source: String, fileName: String) -> CodeArtifact {
        grammar.parse(source: source, fileName: fileName) { root in
            var extractor = JSExtractor(source: source, fileName: fileName, isTypeScript: isTypeScript, root: root)
            return extractor.extract(from: root)
        }
    }
}
