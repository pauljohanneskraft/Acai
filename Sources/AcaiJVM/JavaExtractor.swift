import AcaiCore
import AcaiTreeSitter

/// Walks a Java tree-sitter AST and builds its `CodeArtifact`, sequencing collaborators that each
/// own one concern. Every collaborator is built once, in `init`.
struct JavaExtractor {

    /// Java structural decision-point node types for cyclomatic complexity.
    static let branchNodeKinds: Set<String> = [
        "if_statement", "for_statement", "enhanced_for_statement", "while_statement", "do_statement",
        "catch_clause", "switch_label"
    ]

    /// A `switch_label` carrying a `default` keyword is the fallback arm, not a decision.
    static let complexityFallbackMarkers: [String: Set<String>] = ["switch_label": ["default"]]

    let context: SourceFileContext
    let modifiers: JavaModifiers
    let typeReferences: JavaTypeReferenceResolver
    let parameterExtractor: JavaParameterExtractor
    let memberExtractor: JavaMemberExtractor
    let assignmentSyntax: JavaAssignmentSyntax
    let callSites: CallSiteResolver
    let assignments: AssignmentResolver
    let fieldReads: FieldReadResolver

    var declarations = DeclarationBuilder()

    /// Takes the tree so the declared-type and enum-constant pre-passes run before the collaborators
    /// that read them.
    init(source: String, fileName: String, root: Node) {
        let context = SourceFileContext(source: source, fileName: fileName)
        let declaredTypeNames = TypeNamePrepass(declarationNodeTypes: [
            "class_declaration", "interface_declaration", "enum_declaration",
            "record_declaration", "annotation_type_declaration"
        ]).names(in: root) { $0.child(byFieldName: "name").map { $0.text(in: context) } }

        var declaredEnumConstants: Set<String> = []
        func collectEnumConstants(_ node: Node) {
            if node.nodeType == "enum_constant", let nameNode = node.child(byFieldName: "name") {
                declaredEnumConstants.insert(nameNode.text(in: context))
            }
            for index in 0..<node.childCount {
                node.child(at: index).map(collectEnumConstants)
            }
        }
        collectEnumConstants(root)

        self.context = context
        modifiers = JavaModifiers(context: context)
        let typeReferences = JavaTypeReferenceResolver(context: context)
        self.typeReferences = typeReferences
        parameterExtractor = JavaParameterExtractor(
            context: context, typeReferences: typeReferences, modifiers: modifiers)
        memberExtractor = JavaMemberExtractor(context: context)
        assignmentSyntax = JavaAssignmentSyntax(context: context, declaredEnumConstants: declaredEnumConstants)
        callSites = CallSiteResolver(syntax: JavaCallSiteSyntax(context: context))
        assignments = AssignmentResolver(syntax: assignmentSyntax)
        // Bare identifiers, and the `field` of a `this.<field>` access, are both `identifier` nodes.
        fieldReads = FieldReadResolver(context: context, identifierTypes: ["identifier"])

        declarations.declaredTypeNames = declaredTypeNames
    }

    // MARK: - Public Entry Point

    mutating func extract(from root: Node) -> CodeArtifact {
        walkSourceFile(root)
        declarations.resolveRelationshipNames()
        return declarations.artifact(language: .java, filePath: context.fileName)
    }

    // MARK: - Parse Diagnostics

    func collectParseDiagnostics(from root: Node) -> [ParseDiagnostic] {
        ParseDiagnosticsCollector(context: context).diagnostics(in: root)
    }
}
