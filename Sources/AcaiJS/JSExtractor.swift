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

    // MARK: - Namespace Qualification

    /// Qualifies every type id/qualifiedName with its enclosing structural prefix, recursing into
    /// nested types, so a class inside `namespace Zoo` becomes `Zoo.Animal` (and a class inside
    /// `namespace App { namespace Models { … } }` becomes `App.Models.User`). Top-level types are
    /// unchanged (`prefix == nil` → id stays the simple name). Using the structural parent chain —
    /// rather than each type's `namespace` field — keeps nested namespaces fully qualified, so
    /// edges and inherited-type names to namespaced types resolve during enrichment.
    private static func qualifyIDs(_ types: inout [TypeDeclaration], prefix: String?) {
        for index in types.indices {
            let qualified = prefix.map { "\($0).\(types[index].name)" } ?? types[index].name
            types[index].id = qualified
            types[index].qualifiedName = qualified
            qualifyIDs(&types[index].nestedTypes, prefix: qualified)
        }
    }

    // MARK: - Public Entry Point

    mutating func extract(from root: Node) -> CodeArtifact {
        walkSourceFile(root)

        Self.qualifyIDs(&declarations.types, prefix: nil)

        return declarations.artifact(
            language: isTypeScript ? .typeScript : .javaScript, filePath: context.fileName
        )
    }

    // MARK: - Parse Diagnostics

    func collectParseDiagnostics(from root: Node) -> [ParseDiagnostic] {
        ParseDiagnosticsCollector(context: context).diagnostics(in: root)
    }
}
