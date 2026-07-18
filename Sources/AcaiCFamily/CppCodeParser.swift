import AcaiCore
import AcaiTreeSitter
import TreeSitterCPP

/// Parses C++ source into a `CodeArtifact` using the tree-sitter C++ grammar.
///
/// Owns the unambiguous C++ extensions (`.cpp`, `.cc`, `.cxx`, `.c++`, `.hpp`, `.hh`, `.hxx`, `.h++`,
/// `.ipp`, `.tpp`). The shared `.h` extension is owned by ``CCodeParser``, which routes C++ headers
/// here by content. C++ is a near-superset of C, so the shared ``CFamilyExtractor`` handles both;
/// the C++-only constructs (classes, namespaces, templates, access specifiers, base classes) simply
/// do not appear in a C tree.
public struct CppCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .cpp
    public let fileExtensions: [String] = [
        "cpp", "cc", "cxx", "c++", "hpp", "hh", "hxx", "h++", "ipp", "tpp"
    ]

    public init() {}

    public func parse(source: String, fileName: String) -> CodeArtifact {
        CFamilyTreeSitterParse(dialect: .cpp, grammar: Language(language: tree_sitter_cpp()))
            .parse(source: source, fileName: fileName)
    }
}
