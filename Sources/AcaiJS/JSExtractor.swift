import AcaiCore
import AcaiTreeSitter

/// Walks a tree-sitter AST (JavaScript or TypeScript) and builds its `CodeArtifact`, sequencing
/// collaborators that each own one concern. Every collaborator is built once, in `init`.
struct JSExtractor {

    let context: SourceFileContext
    let isTypeScript: Bool

    let typeReferences: JSTypeReferenceResolver
    let parameterExtractor: JSParameterExtractor
    let memberExtractor: JSMemberExtractor
    let assignmentSyntax: JSAssignmentSyntax
    let callSites: CallSiteResolver
    let assignments: AssignmentResolver
    let fieldReads: FieldReadResolver

    var declarations = DeclarationBuilder()

    /// Call sites made by bare top-level statements (`bootstrap();`), collected during
    /// `walkSourceFile` and attached to a synthetic always-reachable freestanding member.
    var topLevelCallSites: [CallSite] = []

    /// Takes the tree so the declared-type pre-pass runs before the collaborators that read it.
    init(source: String, fileName: String, isTypeScript: Bool, root: Node) {
        let context = SourceFileContext(source: source, fileName: fileName)
        let typeReferences = JSTypeReferenceResolver(context: context, isTypeScript: isTypeScript)
        let declaredTypeNames = TypeNamePrepass(declarationNodeTypes: [
            "class_declaration", "class", "abstract_class_declaration",
            "interface_declaration", "enum_declaration"
        ]).names(in: root) { $0.child(byFieldName: "name").map { $0.text(in: context) } }

        self.context = context
        self.isTypeScript = isTypeScript
        self.typeReferences = typeReferences
        let parameterExtractor = JSParameterExtractor(
            context: context, isTypeScript: isTypeScript, typeReferences: typeReferences)
        self.parameterExtractor = parameterExtractor
        memberExtractor = JSMemberExtractor(
            context: context, isTypeScript: isTypeScript, typeReferences: typeReferences,
            parameterExtractor: parameterExtractor
        )
        assignmentSyntax = JSAssignmentSyntax(context: context)
        callSites = CallSiteResolver(syntax: JSCallSiteSyntax(context: context))
        assignments = AssignmentResolver(syntax: assignmentSyntax)
        // Bare names, `this.<member>` property names, and object-literal shorthands are all
        // identifier-family nodes.
        fieldReads = FieldReadResolver(
            context: context,
            identifierTypes: ["identifier", "property_identifier", "shorthand_property_identifier"]
        )

        declarations.declaredTypeNames = declaredTypeNames
    }

    // MARK: - Public Entry Point

    mutating func extract(from root: Node) -> CodeArtifact {
        walkSourceFile(root)
        // A class inside `namespace Zoo` becomes `Zoo.Animal`, so edges and inherited-type names to
        // namespaced types resolve during enrichment.
        declarations.qualifyNestedTypeIDs()
        return declarations.artifact(
            language: isTypeScript ? .typeScript : .javaScript, filePath: context.fileName
        )
    }
}
