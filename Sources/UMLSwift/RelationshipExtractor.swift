import SwiftSyntax
import UMLCore

enum RelationshipExtractor {

    static func extract(from node: ClassDeclSyntax, typeId: String) -> [Relationship] {
        guard let clause = node.inheritanceClause else { return [] }
        return clause.inheritedTypes.enumerated().map { index, inherited in
            let target = inherited.type.trimmedDescription
            let kind: Relationship.Kind = index == 0 ? .inheritance : .conformance
            return Relationship(kind: kind, source: typeId, target: target)
        }
    }

    static func extract(from node: StructDeclSyntax, typeId: String) -> [Relationship] {
        guard let clause = node.inheritanceClause else { return [] }
        return clause.inheritedTypes.map { inherited in
            Relationship(kind: .conformance, source: typeId, target: inherited.type.trimmedDescription)
        }
    }

    static func extract(from node: EnumDeclSyntax, typeId: String) -> [Relationship] {
        guard let clause = node.inheritanceClause else { return [] }
        return clause.inheritedTypes.map { inherited in
            Relationship(kind: .conformance, source: typeId, target: inherited.type.trimmedDescription)
        }
    }

    static func extract(from node: ProtocolDeclSyntax, typeId: String) -> [Relationship] {
        guard let clause = node.inheritanceClause else { return [] }
        return clause.inheritedTypes.map { inherited in
            Relationship(kind: .conformance, source: typeId, target: inherited.type.trimmedDescription)
        }
    }

    static func extract(from node: ExtensionDeclSyntax, typeId: String) -> [Relationship] {
        let extendedName = node.extendedType.trimmedDescription
        var results = [Relationship(kind: .extension, source: typeId, target: extendedName)]
        if let clause = node.inheritanceClause {
            for inherited in clause.inheritedTypes {
                results.append(
                    Relationship(kind: .conformance, source: extendedName, target: inherited.type.trimmedDescription)
                )
            }
        }
        return results
    }

    static func extract(from node: ActorDeclSyntax, typeId: String) -> [Relationship] {
        guard let clause = node.inheritanceClause else { return [] }
        return clause.inheritedTypes.map { inherited in
            Relationship(kind: .conformance, source: typeId, target: inherited.type.trimmedDescription)
        }
    }
}
