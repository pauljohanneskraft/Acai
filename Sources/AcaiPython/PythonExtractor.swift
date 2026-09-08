import AcaiCore
import AcaiTreeSitter

struct PythonExtractor: TreeSitterExtracting, CallSiteResolving {
    let context: SourceFileContext

    /// The declaration/relationship bookkeeping this extractor accumulates while walking — factored
    /// into its own shared type (`DeclarationCollector`) rather than kept as loose properties here.
    var declarations = DeclarationCollector()
    var topLevelCallSites: [CallSite] = []

    var types: [TypeDeclaration] {
        get { declarations.types }
        set { declarations.types = newValue }
    }
    var relationships: [Relationship] {
        get { declarations.relationships }
        set { declarations.relationships = newValue }
    }
    var freestandingFunctions: [Member] {
        get { declarations.freestandingFunctions }
        set { declarations.freestandingFunctions = newValue }
    }
    var globalVariables: [Member] {
        get { declarations.globalVariables }
        set { declarations.globalVariables = newValue }
    }
    var currentNamespace: String? {
        get { declarations.currentNamespace }
        set { declarations.currentNamespace = newValue }
    }
    var declaredTypeNames: Set<String> {
        get { declarations.declaredTypeNames }
        set { declarations.declaredTypeNames = newValue }
    }

    init(source: String, fileName: String) {
        self.context = SourceFileContext(source: source, fileName: fileName)
    }

    // MARK: - Public Entry Point

    mutating func extract(from root: Node) -> CodeArtifact {
        declaredTypeNames = collectDeclaredTypeNames(
            from: root,
            declarationNodeTypes: ["class_definition"],
            name: { $0.child(byFieldName: "name").map { self.text($0) } }
        )
        walkSourceFile(root)
        declarations.resolveRelationshipNames()
        return declarations.buildArtifact(language: .python, fileName: context.fileName)
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
