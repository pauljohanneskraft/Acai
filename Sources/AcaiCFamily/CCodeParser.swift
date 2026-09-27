import AcaiCore
import AcaiTreeSitter
import TreeSitterC
import TreeSitterCPP

/// Parses C source into a `CodeArtifact` using the tree-sitter C grammar.
///
/// Owns `.c` and the shared `.h` extension. Because `.h` is claimed by both C and C++ but the engine
/// routes each extension to a single parser, this parser content-sniffs every `.h` file
/// (`CFamilyHeaderClassifier`) and, when the header is actually C++, parses it with the C++ grammar
/// and reports `cpp` — the agnostic engine then labels and enriches that file as C++ even though a C
/// source-spec discovered it. Plain C headers and `.c` files are parsed as C.
public struct CCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .c
    public let fileExtensions: [String] = ["c", "h"]

    private let cGrammar = CFamilyGrammar(dialect: .c, language: Language(language: tree_sitter_c()))
    private let cppGrammar = CFamilyGrammar(dialect: .cpp, language: Language(language: tree_sitter_cpp()))

    public init() {}

    public func parse(source: String, fileName: String) -> CodeArtifact {
        let asCpp = fileName.hasSuffix(".h") && CFamilyHeaderClassifier(source: source).looksLikeCpp
        return (asCpp ? cppGrammar : cGrammar).parse(source: source, fileName: fileName)
    }
}

/// One dialect's grammar plus the extractor run over its trees; shared by both parsers so a C++
/// header discovered through `.h` is parsed exactly as a `.cpp` file would be.
struct CFamilyGrammar {
    let dialect: CFamilyDialect
    let grammar: TreeSitterGrammar

    init(dialect: CFamilyDialect, language: Language) {
        self.dialect = dialect
        grammar = TreeSitterGrammar(language: language, sourceLanguage: dialect.sourceLanguage)
    }

    func parse(source: String, fileName: String) -> CodeArtifact {
        grammar.parse(source: source, fileName: fileName) { root in
            var extractor = CFamilyExtractor(source: source, fileName: fileName, dialect: dialect, root: root)
            return extractor.extract(from: root)
        }
    }
}
