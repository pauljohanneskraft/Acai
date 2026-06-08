import SwiftSyntax
import UMLCore

enum RelationshipExtractor {

    // MARK: - Composition Expansion

    /// Expands a potentially composed type (`A & B & C`) into individual type names.
    private static func expandTypeNames(_ typeSyntax: TypeSyntax) -> [String] {
        // Route through `extractTypeReference` so attributes (`@unchecked`,
        // `@retroactive`, `@MainActor`) and optional/array sugar are stripped,
        // keeping edge endpoints consistent with `TypeDeclaration.inheritedTypes`.
        if let composition = typeSyntax.as(CompositionTypeSyntax.self) {
            return composition.elements.map { TypeExtractor.extractTypeReference(from: $0.type).name }
        }
        return [TypeExtractor.extractTypeReference(from: typeSyntax).name]
    }

    // MARK: - Extraction

    static func extract(from node: ClassDeclSyntax, typeId: String) -> [Relationship] {
        guard let clause = node.inheritanceClause else { return [] }
        var results: [Relationship] = []
        var isFirst = true
        for inherited in clause.inheritedTypes {
            for target in expandTypeNames(inherited.type) {
                let kind: Relationship.Kind = isFirst ? .inheritance : .conformance
                results.append(Relationship(kind: kind, source: typeId, target: target))
                isFirst = false
            }
        }
        return results
    }

    static func extract(from node: StructDeclSyntax, typeId: String) -> [Relationship] {
        guard let clause = node.inheritanceClause else { return [] }
        return clause.inheritedTypes.flatMap { inherited in
            expandTypeNames(inherited.type).map { target in
                Relationship(kind: .conformance, source: typeId, target: target)
            }
        }
    }

    static func extract(from node: EnumDeclSyntax, typeId: String) -> [Relationship] {
        guard let clause = node.inheritanceClause else { return [] }
        return clause.inheritedTypes.flatMap { inherited in
            expandTypeNames(inherited.type).map { target in
                Relationship(kind: .conformance, source: typeId, target: target)
            }
        }
    }

    static func extract(from node: ProtocolDeclSyntax, typeId: String) -> [Relationship] {
        guard let clause = node.inheritanceClause else { return [] }
        return clause.inheritedTypes.flatMap { inherited in
            expandTypeNames(inherited.type).map { target in
                Relationship(kind: .conformance, source: typeId, target: target)
            }
        }
    }

    static func extract(from node: ExtensionDeclSyntax, typeId: String) -> [Relationship] {
        // Extensions emit no relationships at parse time. `CodeArtifact.resolvingExtensions()`
        // is the single source of truth: it merges in-codebase extension conformances (so the
        // edge source is the real target id) and drops extensions of external types. Emitting
        // here as well produced dangling `.extension` edges and duplicate conformances.
        []
    }

    static func extract(from node: ActorDeclSyntax, typeId: String) -> [Relationship] {
        guard let clause = node.inheritanceClause else { return [] }
        return clause.inheritedTypes.flatMap { inherited in
            expandTypeNames(inherited.type).map { target in
                Relationship(kind: .conformance, source: typeId, target: target)
            }
        }
    }
}
