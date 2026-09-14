import AcaiCore
import AcaiTreeSitter

// MARK: - PythonTypeDeclarationExtractor

/// Builds a class's `TypeDeclaration` skeleton — kind, generics, inherited types, decorators,
/// location — from its already-resolved `bases`. Knows nothing about a class's body; `PythonExtractor`
/// walks that separately and appends members/nested types/enum cases onto the value this returns.
/// Stateless beyond `context`, mirroring `PythonBaseClassResolver`.
struct PythonTypeDeclarationExtractor {
    let context: SourceFileContext

    struct Signature {
        let name: String
        let qualifiedName: String
        let decorators: [String]
        let bases: PythonBaseClassResolver.Bases
        let accessLevel: AccessLevel
    }

    func declaration(for node: Node, signature: Signature) -> TypeDeclaration {
        let resolver = PythonBaseClassResolver(context: context)
        var generics = signature.bases.generics
        generics.append(contentsOf: resolver.declaredTypeParameters(node))
        return TypeDeclaration(
            id: signature.qualifiedName,
            name: signature.name,
            qualifiedName: signature.qualifiedName,
            kind: resolver.kind(forBaseNames: signature.bases.allNames),
            accessLevel: signature.accessLevel,
            genericParameters: generics,
            inheritedTypes: signature.bases.inherited,
            annotations: signature.decorators,
            location: node.location(in: context)
        )
    }
}

extension PythonExtractor {
    var typeDeclarationExtractor: PythonTypeDeclarationExtractor { PythonTypeDeclarationExtractor(context: context) }
}
