import UMLCore
import UMLTreeSitter

struct RustExtractor: TreeSitterExtracting, CallSiteResolving, AssignmentResolving {
    struct PendingImplMember {
        var member: Member
        let body: Node?
    }

    let context: SourceFileContext

    var types: [TypeDeclaration] = []
    var relationships: [Relationship] = []
    var freestandingFunctions: [Member] = []
    var globalVariables: [Member] = []
    var currentNamespace: String?
    var declaredTypeNames: Set<String> = []
    var pendingImplMembers: [String: [PendingImplMember]] = [:]
    var pendingImplSupertypes: [String: [TypeReference]] = [:]

    init(source: String, fileName: String) {
        self.context = SourceFileContext(source: source, fileName: fileName)
    }

    mutating func extract(from root: Node) -> CodeArtifact {
        declaredTypeNames = collectDeclaredTypeNames(
            from: root,
            declarationNodeTypes: ["struct_item", "enum_item", "trait_item", "type_item"],
            name: { $0.child(byFieldName: "name").map { self.text($0) } }
        )
        walkSourceFile(root)
        applyPendingImpls()
        resolveRelationshipNames()
        return CodeArtifact(
            metadata: .init(sourceLanguage: .rust, filePaths: [context.fileName]),
            types: types,
            relationships: relationships,
            freestandingFunctions: freestandingFunctions,
            globalVariables: globalVariables
        )
    }
}
