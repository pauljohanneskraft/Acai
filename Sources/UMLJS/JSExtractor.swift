import UMLCore
import UMLTreeSitter

/// Walks a tree-sitter AST (JavaScript or TypeScript) and produces UMLCore model types.
struct JSExtractor: TreeSitterExtracting, CallSiteResolving {
    let context: SourceFileContext
    let isTypeScript: Bool

    var types: [TypeDeclaration] = []
    var relationships: [Relationship] = []
    var freestandingFunctions: [Member] = []
    var currentNamespace: String?
    var declaredTypeNames: Set<String> = []

    init(source: String, fileName: String, isTypeScript: Bool) {
        self.context = SourceFileContext(source: source, fileName: fileName)
        self.isTypeScript = isTypeScript
    }

    // MARK: - Shorthands

    /// Builds a qualified ID from an optional namespace and a type name.
    private static func qualifiedId(_ name: String, namespace: String?) -> String {
        namespace.map { "\($0).\(name)" } ?? name
    }

    // MARK: - Public Entry Point

    mutating func extract(from root: Node) -> CodeArtifact {
        declaredTypeNames = collectDeclaredTypeNames(
            from: root,
            declarationNodeTypes: [
                "class_declaration", "class", "abstract_class_declaration",
                "interface_declaration", "enum_declaration"
            ],
            name: { $0.child(byFieldName: "name").map { self.text($0) } }
        )
        walkSourceFile(root)

        // Post-process: qualify type IDs with their namespace so edges resolve correctly.
        for i in types.indices {
            let namespace = types[i].namespace
            let qualifiedTypeName = Self.qualifiedId(types[i].name, namespace: namespace)
            types[i].id = qualifiedTypeName
            types[i].qualifiedName = qualifiedTypeName
        }

        return CodeArtifact(
            metadata: .init(
                sourceLanguage: isTypeScript ? .typeScript : .javaScript,
                filePaths: [context.fileName]
            ),
            types: types,
            relationships: relationships,
            freestandingFunctions: freestandingFunctions
        )
    }
}

// MARK: - Declaration Dispatch & Extraction
