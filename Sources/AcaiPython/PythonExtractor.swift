import AcaiCore
import AcaiTreeSitter

struct PythonExtractor: TreeSitterExtracting, CallSiteResolving {
    let context: SourceFileContext
    let typeReferenceResolver: PythonTypeReferenceResolver
    let baseClassResolver: PythonBaseClassResolver
    let parameterExtractor: PythonParameterExtractor
    let memberExtractor: PythonMemberExtractor
    let typeDeclarationExtractor: PythonTypeDeclarationExtractor

    var types: [TypeDeclaration] = []
    var relationships: [Relationship] = []
    var freestandingFunctions: [Member] = []
    var globalVariables: [Member] = []
    var currentNamespace: String?
    var declaredTypeNames: Set<String> = []
    var topLevelCallSites: [CallSite] = []

    init(source: String, fileName: String) {
        let context = SourceFileContext(source: source, fileName: fileName)
        let typeReferenceResolver = PythonTypeReferenceResolver(context: context)
        let baseClassResolver = PythonBaseClassResolver(context: context, typeReferences: typeReferenceResolver)

        self.context = context
        self.typeReferenceResolver = typeReferenceResolver
        self.baseClassResolver = baseClassResolver
        self.parameterExtractor = PythonParameterExtractor(context: context, typeReferences: typeReferenceResolver)
        self.memberExtractor = PythonMemberExtractor(context: context, typeReferences: typeReferenceResolver)
        self.typeDeclarationExtractor = PythonTypeDeclarationExtractor(
            context: context, baseClassResolver: baseClassResolver
        )
    }

    // MARK: - Public Entry Point

    mutating func extract(from root: Node) -> CodeArtifact {
        declaredTypeNames = collectDeclaredTypeNames(
            from: root,
            declarationNodeTypes: ["class_definition"],
            name: { $0.child(byFieldName: "name").map { self.text($0) } }
        )
        walkSourceFile(root)
        resolveRelationshipNames()
        return buildArtifact(language: .python)
    }

    // MARK: - Access Level (naming convention)

    /// Python has no access keywords; visibility is conveyed by leading underscores (dunders are
    /// public, `__x` is name-mangled private, `_x` is protected).
    func accessLevel(forName name: String) -> AccessLevel {
        if name.hasPrefix("__") && name.hasSuffix("__") { return .public }
        if name.hasPrefix("__") { return .private }
        if name.hasPrefix("_") { return .protected }
        return .public
    }
}
