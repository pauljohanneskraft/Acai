import SwiftSyntax
import UMLCore

extension TypeExtractor {

    // MARK: - Type Declaration Extraction

    static func extractClass(from node: ClassDeclSyntax, fileName: String, namespace: String?) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .class,
            accessLevel: extractAccessLevel(from: node.modifiers),
            modifiers: extractModifiers(from: node.modifiers),
            genericParameters: extractGenericParameters(from: node.genericParameterClause),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            annotations: extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocation(of: node, fileName: fileName)
        )
    }

    static func extractStruct(from node: StructDeclSyntax, fileName: String, namespace: String?) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .struct,
            accessLevel: extractAccessLevel(from: node.modifiers),
            modifiers: extractModifiers(from: node.modifiers),
            genericParameters: extractGenericParameters(from: node.genericParameterClause),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            annotations: extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocation(of: node, fileName: fileName)
        )
    }

    static func extractEnum(from node: EnumDeclSyntax, fileName: String, namespace: String?) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .enum,
            accessLevel: extractAccessLevel(from: node.modifiers),
            modifiers: extractModifiers(from: node.modifiers),
            genericParameters: extractGenericParameters(from: node.genericParameterClause),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            annotations: extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocation(of: node, fileName: fileName)
        )
    }

    static func extractProtocol(
        from node: ProtocolDeclSyntax, fileName: String, namespace: String?
    ) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .protocol,
            accessLevel: extractAccessLevel(from: node.modifiers),
            modifiers: extractModifiers(from: node.modifiers),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            annotations: extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocation(of: node, fileName: fileName)
        )
    }

    static func extractExtension(
        from node: ExtensionDeclSyntax, fileName: String, namespace: String?
    ) -> TypeDeclaration {
        let extendedName = node.extendedType.trimmedDescription
        let name = extendedName
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: "extension.\(qualifiedName)",
            name: name,
            qualifiedName: qualifiedName,
            kind: .extension,
            accessLevel: extractAccessLevel(from: node.modifiers),
            modifiers: extractModifiers(from: node.modifiers),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            annotations: extractAttributes(from: node.attributes),
            extensionOf: extendedName,
            namespace: namespace,
            location: sourceLocation(of: node, fileName: fileName)
        )
    }

    static func extractTypeAlias(
        from node: TypeAliasDeclSyntax, fileName: String, namespace: String?
    ) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .typeAlias,
            accessLevel: extractAccessLevel(from: node.modifiers),
            modifiers: extractModifiers(from: node.modifiers),
            genericParameters: extractGenericParameters(from: node.genericParameterClause),
            inheritedTypes: [extractTypeReference(from: node.initializer.value)],
            annotations: extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocation(of: node, fileName: fileName)
        )
    }

    static func extractActor(from node: ActorDeclSyntax, fileName: String, namespace: String?) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .class,
            accessLevel: extractAccessLevel(from: node.modifiers),
            modifiers: extractModifiers(from: node.modifiers),
            genericParameters: extractGenericParameters(from: node.genericParameterClause),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            annotations: ["@actor"] + extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocation(of: node, fileName: fileName)
        )
    }

    // MARK: - Source Location

    static func sourceLocation(of node: some SyntaxProtocol, fileName: String) -> UMLCore.SourceLocation {
        let position = node.positionAfterSkippingLeadingTrivia
        let sourceFile = node.root.as(SourceFileSyntax.self)!
        let converter = SourceLocationConverter(fileName: fileName, tree: sourceFile)
        let location = converter.location(for: position)
        return UMLCore.SourceLocation(
            filePath: fileName,
            line: location.line,
            column: location.column
        )
    }
}
