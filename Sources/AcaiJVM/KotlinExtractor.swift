import AcaiCore
import AcaiTreeSitter

/// Extracts type declarations, relationships, and freestanding functions
/// from a Kotlin source file's tree-sitter AST.
struct KotlinExtractor: TreeSitterExtracting, CallSiteResolving {

    /// Kotlin structural decision-point node types for cyclomatic complexity (`when` entries, `if`/
    /// loops, `catch`).
    static let branchNodeKinds: Set<String> = [
        "if_expression", "for_statement", "while_statement", "do_while_statement",
        "when_entry", "catch_block"
    ]

    // MARK: - State

    let context: SourceFileContext
    var types: [TypeDeclaration] = []
    var relationships: [Relationship] = []
    var freestandingFunctions: [Member] = []
    var currentNamespace: String?
    var declaredTypeNames: Set<String> = []

    init(source: String, fileName: String) {
        self.context = SourceFileContext(source: source, fileName: fileName)
    }

    // MARK: - Public Entry Point

    mutating func extract(from root: Node) -> CodeArtifact {
        declaredTypeNames = collectDeclaredTypeNames(
            from: root,
            declarationNodeTypes: ["class_declaration", "object_declaration"],
            name: { $0.firstChild(withType: "type_identifier").map { self.text($0) } }
        )
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
