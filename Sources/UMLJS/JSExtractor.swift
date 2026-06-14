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
        Self.qualifyIDs(&types, prefix: nil)

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
