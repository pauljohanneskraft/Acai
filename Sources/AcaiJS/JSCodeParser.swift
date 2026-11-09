import AcaiCore
import AcaiTreeSitter
import TreeSitterTSX
import TreeSitterTypeScript

/// Unified parser for both JavaScript and TypeScript (including JSX/TSX). When `isTypeScript` is
/// true, type annotations, interfaces, type aliases, and enums are parsed; when false those
/// constructs are skipped.
public struct JSCodeParser: CodeParser {
    public let isTypeScript: Bool

    public var language: CodeArtifact.SourceLanguage { isTypeScript ? .typeScript : .javaScript }
    public var fileExtensions: [String] {
        isTypeScript ? ["ts", "mts", "cts", "tsx"] : ["js", "jsx", "mjs", "cjs"]
    }

    private let typeScript: JSGrammar
    private let tsx: JSGrammar

    public init(isTypeScript: Bool = true) {
        self.isTypeScript = isTypeScript
        let sourceLanguage: CodeArtifact.SourceLanguage = isTypeScript ? .typeScript : .javaScript
        typeScript = JSGrammar(
            isTypeScript: isTypeScript,
            language: Language(language: tree_sitter_typescript()),
            sourceLanguage: sourceLanguage
        )
        tsx = JSGrammar(
            isTypeScript: isTypeScript,
            language: Language(language: tree_sitter_tsx()),
            sourceLanguage: sourceLanguage
        )
    }

    public func parse(source: String, fileName: String) -> CodeArtifact {
        grammar(for: fileName).parse(source: source, fileName: fileName)
    }

    /// Only the extension says whether `<T>x` is a cast or JSX, so the source is never sniffed.
    private func grammar(for fileName: String) -> JSGrammar {
        let name = fileName.lowercased()
        return ["ts", "mts", "cts"].contains { name.hasSuffix(".\($0)") } ? typeScript : tsx
    }
}

struct JSGrammar {
    let isTypeScript: Bool
    let grammar: TreeSitterGrammar

    init(isTypeScript: Bool, language: Language, sourceLanguage: CodeArtifact.SourceLanguage) {
        self.isTypeScript = isTypeScript
        grammar = TreeSitterGrammar(language: language, sourceLanguage: sourceLanguage)
    }

    func parse(source: String, fileName: String) -> CodeArtifact {
        grammar.parse(source: source, fileName: fileName) { root in
            var extractor = JSExtractor(source: source, fileName: fileName, isTypeScript: isTypeScript, root: root)
            return extractor.extract(from: root)
        }
    }
}
