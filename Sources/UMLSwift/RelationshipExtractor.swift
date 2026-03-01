import SwiftSyntax
import UMLCore

enum RelationshipExtractor {

    // MARK: - Composition Expansion

    /// Expands a potentially composed type (`A & B & C`) into individual type names.
    private static func expandTypeNames(_ typeSyntax: TypeSyntax) -> [String] {
        if let composition = typeSyntax.as(CompositionTypeSyntax.self) {
            return composition.elements.map { $0.type.trimmedDescription }
        }
        return [typeSyntax.trimmedDescription]
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
        let extendedName = node.extendedType.trimmedDescription
        var results = [Relationship(kind: .extension, source: typeId, target: extendedName)]
        if let clause = node.inheritanceClause {
            for inherited in clause.inheritedTypes {
                for target in expandTypeNames(inherited.type) {
                    results.append(Relationship(kind: .conformance, source: extendedName, target: target))
                }
            }
        }
        return results
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
