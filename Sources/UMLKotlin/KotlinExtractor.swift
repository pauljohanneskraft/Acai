import UMLCore
import UMLTreeSitter

/// Extracts type declarations, relationships, and freestanding functions
/// from a Kotlin source file's tree-sitter AST.
struct KotlinExtractor: TreeSitterExtracting, CallSiteResolving {

    // MARK: - State

    let context: SourceFileContext
    var types: [TypeDeclaration] = []
    var relationships: [Relationship] = []
    var freestandingFunctions: [Member] = []
    var currentNamespace: String?

    init(source: String, fileName: String) {
        self.context = SourceFileContext(source: source, fileName: fileName)
    }

    // MARK: - Public Entry Point

    mutating func extract(from root: Node) -> CodeArtifact {
        walkSourceFile(root)
        resolveRelationshipNames()
        return buildArtifact(language: .kotlin)
    }

    // MARK: - Kotlin-Specific Helpers

    /// Shorthand for ``hasAnonymousKeyword(_:in:)``.
    func hasKeyword(_ keyword: String, in node: Node) -> Bool {
        hasAnonymousKeyword(keyword, in: node)
    }

    /// Returns whether the node declares `val` or `var` via a `binding_pattern_kind` child.
    /// Tree-sitter-kotlin wraps `val`/`var` in `[binding_pattern_kind] → [val]`.
    func bindingKind(of node: Node) -> String? {
        guard let bindingPatternNode = node.firstChild(withType: "binding_pattern_kind") else { return nil }
        let bindingText = text(bindingPatternNode).trimmingCharacters(in: .whitespaces)
        return (bindingText == "val" || bindingText == "var") ? bindingText : nil
    }
}
