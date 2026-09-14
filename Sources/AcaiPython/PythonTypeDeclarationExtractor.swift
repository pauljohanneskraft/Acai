import AcaiCore
import AcaiTreeSitter

// MARK: - PythonTypeDeclarationExtractor

/// Builds a class's `TypeDeclaration` skeleton — kind, generics, inherited types, decorators,
/// location — from its already-resolved `bases`. Knows nothing about a class's body; `PythonExtractor`
/// walks that separately and appends members/nested types/enum cases onto the value this returns.
/// Stateless beyond `context`, mirroring `PythonBaseClassResolver`.
struct PythonTypeDeclarationExtractor {
    let context: SourceFileContext

    func declaration(
        for node: Node,
        name: String,
        qualifiedName: String,
        decorators: [String],
        bases: PythonBaseClassResolver.Bases,
        accessLevel: AccessLevel
    ) -> TypeDeclaration {
        let resolver = PythonBaseClassResolver(context: context)
        var generics = bases.generics
        generics.append(contentsOf: resolver.declaredTypeParameters(node))
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: resolver.kind(forBaseNames: bases.allNames),
            accessLevel: accessLevel,
            genericParameters: generics,
            inheritedTypes: bases.inherited,
            annotations: decorators,
            location: node.location(in: context)
        )
    }
}

extension PythonExtractor {
    var typeDeclarationExtractor: PythonTypeDeclarationExtractor { PythonTypeDeclarationExtractor(context: context) }
}
