import UMLCore
import UMLTreeSitter

/// Walks a tree-sitter Python AST and produces UMLCore model types.
///
/// Conforms to ``CallSiteResolving`` and ``AssignmentResolving`` (sequence-diagram support) on top of
/// the shared ``TreeSitterExtracting`` infrastructure. Python's distinguishing trait: instance fields
/// are not declared in the class body — they appear as `self.x = …` inside methods — so the member
/// extractor synthesises properties from those assignments (see `PythonExtractor+Members`).
struct PythonExtractor: TreeSitterExtracting, CallSiteResolving {
    let context: SourceFileContext

    var types: [TypeDeclaration] = []
    var relationships: [Relationship] = []
    var freestandingFunctions: [Member] = []
    var globalVariables: [Member] = []
    var currentNamespace: String?
    var declaredTypeNames: Set<String> = []

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
        resolveRelationshipNames()
        return CodeArtifact(
            metadata: .init(sourceLanguage: .python, filePaths: [context.fileName]),
            types: types,
            relationships: relationships,
            freestandingFunctions: freestandingFunctions,
            globalVariables: globalVariables
        )
    }

    // MARK: - Access Level (naming convention)

    /// Python has no access keywords; visibility is conveyed by leading underscores.
    /// Dunders (`__init__`) are public; `__x` (not a dunder) → private (name-mangled); `_x` →
    /// protected; plain names → public.
    func accessLevel(forName name: String) -> AccessLevel {
        if name.hasPrefix("__") && name.hasSuffix("__") { return .public }
        if name.hasPrefix("__") { return .private }
        if name.hasPrefix("_") { return .protected }
        return .public
    }
}
