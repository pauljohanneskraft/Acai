import SwiftSyntax
import AcaiCore

/// Builds a `TypeDeclaration` from each kind of Swift type declaration (class, struct, enum,
/// protocol, extension, type alias, actor).
struct TypeDeclarationExtractor {

    private let signatures = DeclarationSignatureExtractor()
    private let typeReferences = TypeReferenceExtractor()
    private let sourceLocations: SourceLocationResolver

    init(sourceLocations: SourceLocationResolver) {
        self.sourceLocations = sourceLocations
    }

    func extractClass(from node: ClassDeclSyntax, namespace: String?) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .class,
            accessLevel: signatures.extractAccessLevel(from: node.modifiers),
            modifiers: signatures.extractModifiers(from: node.modifiers),
            genericParameters: signatures.extractGenericParameters(
                from: node.genericParameterClause, whereClause: node.genericWhereClause),
            inheritedTypes: typeReferences.extractInheritedTypes(from: node.inheritanceClause),
            annotations: signatures.extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocations.sourceLocation(of: node)
        )
    }

    func extractStruct(from node: StructDeclSyntax, namespace: String?) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .struct,
            accessLevel: signatures.extractAccessLevel(from: node.modifiers),
            modifiers: signatures.extractModifiers(from: node.modifiers),
            genericParameters: signatures.extractGenericParameters(
                from: node.genericParameterClause, whereClause: node.genericWhereClause),
            inheritedTypes: typeReferences.extractInheritedTypes(from: node.inheritanceClause),
            annotations: signatures.extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocations.sourceLocation(of: node)
        )
    }

    func extractEnum(from node: EnumDeclSyntax, namespace: String?) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .enum,
            accessLevel: signatures.extractAccessLevel(from: node.modifiers),
            modifiers: signatures.extractModifiers(from: node.modifiers),
            genericParameters: signatures.extractGenericParameters(
                from: node.genericParameterClause, whereClause: node.genericWhereClause),
            inheritedTypes: typeReferences.extractInheritedTypes(from: node.inheritanceClause),
            annotations: signatures.extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocations.sourceLocation(of: node)
        )
    }

    func extractProtocol(
        from node: ProtocolDeclSyntax, namespace: String?
    ) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .protocol,
            accessLevel: signatures.extractAccessLevel(from: node.modifiers),
            modifiers: signatures.extractModifiers(from: node.modifiers),
            genericParameters: node.primaryAssociatedTypeClause?.primaryAssociatedTypes.map {
                GenericParameter(name: $0.name.text)
            } ?? [],
            inheritedTypes: typeReferences.extractInheritedTypes(from: node.inheritanceClause),
            annotations: signatures.extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocations.sourceLocation(of: node)
        )
    }

    func extractExtension(
        from node: ExtensionDeclSyntax, namespace: String?
    ) -> TypeDeclaration {
        let extendedName = node.extendedType.trimmedDescription
        let name = extendedName
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: "extension.\(qualifiedName)",
            name: name,
            qualifiedName: qualifiedName,
            kind: .extension,
            accessLevel: signatures.extractAccessLevel(from: node.modifiers),
            modifiers: signatures.extractModifiers(from: node.modifiers),
            inheritedTypes: typeReferences.extractInheritedTypes(from: node.inheritanceClause),
            annotations: signatures.extractAttributes(from: node.attributes),
            extensionOf: extendedName,
            namespace: namespace,
            location: sourceLocations.sourceLocation(of: node)
        )
    }

    func extractTypeAlias(
        from node: TypeAliasDeclSyntax, namespace: String?
    ) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .typeAlias,
            accessLevel: signatures.extractAccessLevel(from: node.modifiers),
            modifiers: signatures.extractModifiers(from: node.modifiers),
            genericParameters: signatures.extractGenericParameters(
                from: node.genericParameterClause, whereClause: node.genericWhereClause),
            inheritedTypes: [typeReferences.extractTypeReference(from: node.initializer.value)],
            annotations: signatures.extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocations.sourceLocation(of: node)
        )
    }

    func extractActor(from node: ActorDeclSyntax, namespace: String?) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .actor,
            accessLevel: signatures.extractAccessLevel(from: node.modifiers),
            modifiers: signatures.extractModifiers(from: node.modifiers),
            genericParameters: signatures.extractGenericParameters(
                from: node.genericParameterClause, whereClause: node.genericWhereClause),
            inheritedTypes: typeReferences.extractInheritedTypes(from: node.inheritanceClause),
            annotations: signatures.extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocations.sourceLocation(of: node)
        )
    }
}
