import AcaiCore
import AcaiTreeSitter

/// Walks a Kotlin file and builds its `CodeArtifact`, sequencing collaborators that each own one
/// concern. Every collaborator is built once, in `init`.
struct KotlinExtractor {

    /// Kotlin structural decision-point node types for cyclomatic complexity (`when` entries, `if`/
    /// loops, `catch`).
    static let branchNodeKinds: Set<String> = [
        "if_expression", "for_statement", "while_statement", "do_while_statement",
        "when_entry", "catch_block"
    ]

    let context: SourceFileContext
    let assignmentSyntax: KotlinAssignmentSyntax
    let callSites: CallSiteResolver
    let assignments: AssignmentResolver
    let fieldReads: FieldReadResolver

    var declarations = DeclarationBuilder()

    /// Takes the tree so the declared-type pre-pass runs before the collaborators that read it.
    init(source: String, fileName: String, root: Node) {
        let context = SourceFileContext(source: source, fileName: fileName)
        let declaredTypeNames = TypeNamePrepass(declarationNodeTypes: ["class_declaration", "object_declaration"])
            .names(in: root) { $0.firstChild(withType: "type_identifier").map { $0.text(in: context) } }

        self.context = context
        assignmentSyntax = KotlinAssignmentSyntax(context: context)
        callSites = CallSiteResolver(
            syntax: KotlinCallSiteSyntax(context: context, declaredTypeNames: declaredTypeNames)
        )
        assignments = AssignmentResolver(syntax: assignmentSyntax)
        // Bare references and `this.<prop>` navigation members are both `simple_identifier` nodes.
        fieldReads = FieldReadResolver(context: context, identifierTypes: ["simple_identifier"])

        declarations.declaredTypeNames = declaredTypeNames
    }

    // MARK: - Public Entry Point

    mutating func extract(from root: Node) -> CodeArtifact {
        walkSourceFile(root)
        declarations.resolveRelationshipNames()
        return declarations.artifact(language: .kotlin, filePath: context.fileName)
    }

    // MARK: - Kotlin-Specific Helpers

    func hasKeyword(_ keyword: String, in node: Node) -> Bool {
        node.hasAnonymousChild(keyword, in: context)
    }

    /// Returns whether the node declares `val` or `var` via a `binding_pattern_kind` child.
    /// Tree-sitter-kotlin wraps `val`/`var` in `[binding_pattern_kind] → [val]`.
    func bindingKind(of node: Node) -> String? {
        guard let bindingPatternNode = node.firstChild(withType: "binding_pattern_kind") else { return nil }
        let bindingText = bindingPatternNode.text(in: context).trimmingCharacters(in: .whitespaces)
        return (bindingText == "val" || bindingText == "var") ? bindingText : nil
    }
}
