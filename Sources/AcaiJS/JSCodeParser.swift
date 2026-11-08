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

    /// Chosen by extension, never by sniffing the source: the two grammars read `<T>` differently and
    /// only the extension says which reading the author meant. `.tsx` and every JavaScript extension
    /// take TSX — JavaScript has no `<T>x` cast for JSX to clash with, so it loses nothing by it,
    /// whereas the TypeScript grammar has no JSX at all and turns every element into an `ERROR` node.
    private func grammar(for fileName: String) -> JSGrammar {
        ["ts", "mts", "cts"].contains { fileName.hasSuffix(".\($0)") } ? typeScript : tsx
    }
}

/// One grammar plus the extractor run over its trees, so a `.tsx` file yields the shapes a `.ts`
/// file would and a `.jsx` file those of a `.js` file.
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
