import AcaiCore
import AcaiTreeSitter
import TreeSitterC
import TreeSitterCPP

/// Parses C source into a `CodeArtifact` using the tree-sitter C grammar.
///
/// Owns `.c` and the shared `.h` extension. Because `.h` is claimed by both C and C++ but the engine
/// routes each extension to a single parser, this parser content-sniffs every `.h` file
/// (``CFamilyHeaderClassifier``) and, when the header is actually C++, parses it with the C++ grammar
/// and reports `cpp` — the agnostic engine then labels and enriches that file as C++ even though a C
/// source-spec discovered it. Plain C headers and `.c` files are parsed as C.
public struct CCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .c
    public let fileExtensions: [String] = ["c", "h"]

    public init() {}

    public func parse(source: String, fileName: String) -> CodeArtifact {
        let asCpp = fileName.hasSuffix(".h") && CFamilyHeaderClassifier(source: source).looksLikeCpp
        let dialect: CFamilyDialect = asCpp ? .cpp : .c
        let grammar = asCpp ? Language(language: tree_sitter_cpp()) : Language(language: tree_sitter_c())
        return CFamilyTreeSitterParse(dialect: dialect, grammar: grammar)
            .parse(source: source, fileName: fileName)
    }
}

/// The shared tree-sitter parse step for both C-family parsers: set up the grammar, walk the tree
/// with a ``CFamilyExtractor`` for the given dialect, and surface parse diagnostics.
struct CFamilyTreeSitterParse {
    let dialect: CFamilyDialect
    let grammar: Language

    func parse(source: String, fileName: String) -> CodeArtifact {
        let loader = TreeSitterGrammar(language: grammar, sourceLanguage: dialect.sourceLanguage)
        guard let parser = loader.makeParser() else {
            return loader.loadFailureArtifact(fileName: fileName)
        }
        guard let tree = parser.parse(source), let root = tree.rootNode else {
            return CodeArtifact(metadata: .init(sourceLanguage: dialect.sourceLanguage, filePaths: [fileName]))
        }
        var extractor = CFamilyExtractor(source: source, fileName: fileName, dialect: dialect)
        var artifact = extractor.extract(from: root)
        // Surface concrete ERROR/missing nodes from the best-effort tree so partial output is flagged.
        if root.hasError {
            artifact.metadata.parseDiagnostics = extractor.collectParseDiagnostics(from: root)
        }
        return artifact
    }
}
