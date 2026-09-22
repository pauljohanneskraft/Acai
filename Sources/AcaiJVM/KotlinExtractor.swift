import AcaiCore
import AcaiTreeSitter

/// Walks a Kotlin file and builds its `CodeArtifact`, sequencing collaborators that each own one
/// concern. Every collaborator is built once, in `init`.
struct KotlinExtractor {

    let context: SourceFileContext
    let modifiers: KotlinModifiers
    let typeReferences: KotlinTypeReferenceResolver
    let parameterExtractor: KotlinParameterExtractor
    let memberExtractor: KotlinMemberExtractor

    var declarations = DeclarationBuilder()

    /// Takes the tree so the declared-type pre-pass runs before the collaborators that read it.
    init(source: String, fileName: String, root: Node) {
        let context = SourceFileContext(source: source, fileName: fileName)
        let declaredTypeNames = TypeNamePrepass(declarationNodeTypes: ["class_declaration", "object_declaration"])
            .names(in: root) { $0.firstChild(withType: "type_identifier").map { $0.text(in: context) } }

        self.context = context
        modifiers = KotlinModifiers(context: context)
        typeReferences = KotlinTypeReferenceResolver(context: context)
        parameterExtractor = KotlinParameterExtractor(
            context: context, typeReferences: typeReferences, modifiers: modifiers)
        let assignmentSyntax = KotlinAssignmentSyntax(context: context)
        memberExtractor = KotlinMemberExtractor(
            context: context, typeReferences: typeReferences, modifiers: modifiers,
            parameterExtractor: parameterExtractor, assignmentSyntax: assignmentSyntax,
            callSites: CallSiteResolver(
                syntax: KotlinCallSiteSyntax(context: context, declaredTypeNames: declaredTypeNames)
            ),
            assignments: AssignmentResolver(syntax: assignmentSyntax),
            // Bare references and `this.<prop>` navigation members are both `simple_identifier` nodes.
            fieldReads: FieldReadResolver(context: context, identifierTypes: ["simple_identifier"]),
            declaredTypeNames: declaredTypeNames
        )

        declarations.declaredTypeNames = declaredTypeNames
    }

    // MARK: - Public Entry Point

    mutating func extract(from root: Node) -> CodeArtifact {
        walkSourceFile(root)
        declarations.resolveRelationshipNames()
        return declarations.artifact(language: .kotlin, filePath: context.fileName)
    }

    // MARK: - Function Declaration

    /// An extension function (`fun String.hello() {}`) also records its receiver as an `.extension`
    /// edge, which only the extractor's declaration state can hold.
    mutating func extractFunctionDeclaration(_ node: Node, scope: CallSiteScope = CallSiteScope()) -> Member {
        if let receiverRef = memberExtractor.receiverType(of: node) {
            let name = node.firstChild(withType: "simple_identifier").map { $0.text(in: context) } ?? "_anonymous"
            declarations.relationships.append(
                Relationship(kind: .extension, source: name, target: receiverRef.name)
            )
        }
        return memberExtractor.functionDeclaration(node, scope: scope)
    }
}
