import Foundation
import AcaiCore
import AcaiTreeSitter

/// Walks a Dart file and builds its `CodeArtifact`, sequencing collaborators that each own one
/// concern. Every collaborator is built once, in `init`.
struct DartExtractor {

    static let branchNodeKinds: Set<String> = [
        "if_statement", "for_statement", "for_element", "while_statement", "do_statement",
        "switch_statement_case", "switch_expression_case", "catch_clause"
    ]

    let context: SourceFileContext
    let typeReferences: DartTypeReferenceResolver
    let memberExtractor: DartMemberExtractor
    let annotations: DartAnnotations
    let assignmentSyntax: DartAssignmentSyntax
    let callSites: CallSiteResolver
    let assignments: AssignmentResolver
    let fieldReads: FieldReadResolver

    var declarations = DeclarationBuilder()

    /// Takes the tree so the declared-type pre-pass runs before the collaborators that read it.
    init(source: String, fileName: String, root: Node) {
        let context = SourceFileContext(source: source, fileName: fileName)
        let typeReferences = DartTypeReferenceResolver(context: context)
        let declaredTypeNames = TypeNamePrepass(declarationNodeTypes: [
            "class_definition", "enum_declaration", "mixin_declaration",
            "extension_declaration", "extension_type_declaration"
        ]).names(in: root) { $0.child(byFieldName: "name").map { $0.text(in: context) } }

        self.context = context
        self.typeReferences = typeReferences
        memberExtractor = DartMemberExtractor(
            context: context, typeReferences: typeReferences,
            parameterExtractor: DartParameterExtractor(context: context, typeReferences: typeReferences),
            declaredTypeNames: declaredTypeNames
        )
        annotations = DartAnnotations(context: context)
        assignmentSyntax = DartAssignmentSyntax(context: context)
        callSites = CallSiteResolver(
            syntax: DartCallSiteSyntax(context: context, declaredTypeNames: declaredTypeNames)
        )
        assignments = AssignmentResolver(syntax: assignmentSyntax)
        // Bare references and `this.<prop>` navigation members are both `identifier` nodes.
        fieldReads = FieldReadResolver(context: context, identifierTypes: ["identifier"])

        declarations.declaredTypeNames = declaredTypeNames
    }

    // MARK: - Public Entry Point

    mutating func extract(from root: Node) -> CodeArtifact {
        walkSourceFile(root)
        return declarations.artifact(language: .dart, filePath: context.fileName)
    }

    /// A `function_body` node carries its own optional `async`/`async*`/`sync*` marker as an
    /// anonymous leaf child, ahead of its `=>` expression or `block`.
    func isAsyncFunctionBody(_ node: Node) -> Bool {
        ["async", "async*", "sync*"].contains { node.hasAnonymousChild($0, in: context) }
    }
}
