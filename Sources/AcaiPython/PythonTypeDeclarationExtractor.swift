import AcaiCore
import AcaiTreeSitter

// MARK: - PythonTypeDeclarationExtractor

/// Builds a class's `TypeDeclaration` skeleton — kind, generics, inherited types, decorators,
/// location — from its already-resolved `bases`. Knows nothing about a class's body; `PythonExtractor`
/// walks that separately and appends members/nested types/enum cases onto the value this returns.
struct PythonTypeDeclarationExtractor {
    let context: SourceFileContext
    let baseClassResolver: PythonBaseClassResolver

    struct Signature {
        let name: String
        let qualifiedName: String
        let decorators: [String]
        let bases: PythonBaseClassResolver.Bases
        let accessLevel: AccessLevel
    }

    func declaration(for node: Node, signature: Signature) -> TypeDeclaration {
        var generics = signature.bases.generics
        generics.append(contentsOf: baseClassResolver.declaredTypeParameters(node))
        return TypeDeclaration(
            id: signature.qualifiedName,
            name: signature.name,
            qualifiedName: signature.qualifiedName,
            kind: baseClassResolver.kind(forBaseNames: signature.bases.allNames),
            accessLevel: signature.accessLevel,
            genericParameters: generics,
            inheritedTypes: signature.bases.inherited,
            annotations: signature.decorators,
            location: node.location(in: context)
        )
    }
}
