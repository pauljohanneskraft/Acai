import UMLCore
import UMLTreeSitter

// MARK: - Type Declarations

extension KotlinExtractor {

    // MARK: - Class Declaration

    mutating func extractClassDeclaration(_ node: Node) -> TypeDeclaration? {
        let modifierInfo = extractModifiers(node.firstChild(withType: "modifiers"))

        if node.hasChild(withType: "enum_class_body") {
            return extractEnumClassDeclaration(node, modifierInfo: modifierInfo)
        }

        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)

        let generics = extractTypeParameters(node.firstChild(withType: "type_parameters"))
        let ctorNode = node.firstChild(withType: "primary_constructor")
        let ctorAccess = ctorNode
            .flatMap { $0.firstChild(withType: "modifiers") }
            .map { extractModifiers($0).accessLevel } ?? modifierInfo.accessLevel
        let ctorParams = extractPrimaryConstructorParams(ctorNode)
        let supertypes = classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        let isAnnotation = node.firstChild(withType: "modifiers")?.namedChildren()
            .contains { $0.nodeType == "class_modifier" && text($0) == "annotation" } ?? false

        var typeDecl = TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName,
            kind: isAnnotation ? .annotation : .class,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            genericParameters: generics, inheritedTypes: supertypes.map(\.typeRef),
            annotations: modifierInfo.annotations, namespace: currentNamespace, location: loc(node)
        )

        // Promoted constructor properties — each carries its own access level.
        for constructorParam in ctorParams where constructorParam.isProperty {
            var modifiers = constructorParam.modifiers
            if constructorParam.isReadOnly { modifiers.append(.readonly) }
            typeDecl.members.append(Member(
                name: constructorParam.parameter.internalName, kind: .property,
                accessLevel: constructorParam.accessLevel, modifiers: modifiers,
                type: constructorParam.parameter.type, annotations: constructorParam.annotations
            ))
        }
        if !ctorParams.isEmpty {
            typeDecl.members.append(Member(
                name: "init", kind: .initializer,
                accessLevel: ctorAccess,
                parameters: ctorParams.map(\.parameter)
            ))
        }

        for supertype in supertypes {
            relationships.append(Relationship(
                kind: supertype.isClassInheritance ? .inheritance : .conformance,
                source: qualifiedTypeName, target: supertype.typeRef.name))
        }
        if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Interface

    mutating func extractInterfaceDeclaration(_ node: Node) -> TypeDeclaration? {
        let modifierInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)

        let generics = extractTypeParameters(node.firstChild(withType: "type_parameters"))
        let supertypes = classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        var typeDecl = TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName, kind: .interface,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            genericParameters: generics, inheritedTypes: supertypes.map(\.typeRef),
            annotations: modifierInfo.annotations, namespace: currentNamespace, location: loc(node)
        )
        for supertype in supertypes {
            relationships.append(
                Relationship(kind: .conformance, source: qualifiedTypeName, target: supertype.typeRef.name)
            )
        }
        if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Object Declaration

    mutating func extractObjectDeclaration(_ node: Node) -> TypeDeclaration? {
        let modifierInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)
        let supertypes = classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        var typeDecl = TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName, kind: .object,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            inheritedTypes: supertypes.map(\.typeRef),
            annotations: modifierInfo.annotations, namespace: currentNamespace, location: loc(node)
        )
        for supertype in supertypes {
            relationships.append(Relationship(
                kind: supertype.isClassInheritance ? .inheritance : .conformance,
                source: qualifiedTypeName, target: supertype.typeRef.name))
        }
        if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Companion Object

    mutating func extractCompanionObject(_ node: Node) -> TypeDeclaration? {
        let name = node.firstChild(withType: "type_identifier").map { text($0) } ?? "Companion"
        let qualifiedTypeName = qualifiedName(name)
        let supertypes = classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        var typeDecl = TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName,
            kind: .object, accessLevel: .public, modifiers: [.static],
            inheritedTypes: supertypes.map(\.typeRef),
            namespace: currentNamespace, location: loc(node)
        )
        for supertype in supertypes {
            relationships.append(Relationship(
                kind: supertype.isClassInheritance ? .inheritance : .conformance,
                source: qualifiedTypeName, target: supertype.typeRef.name))
        }
        if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Enum Class

    mutating func extractEnumClassDeclaration(
        _ node: Node,
        modifierInfo: ModifierInfo
    ) -> TypeDeclaration? {
        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)

        let generics = extractTypeParameters(node.firstChild(withType: "type_parameters"))
        let supertypes = classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        var typeDecl = TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName, kind: .enum,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            genericParameters: generics, inheritedTypes: supertypes.map(\.typeRef),
            annotations: modifierInfo.annotations, namespace: currentNamespace, location: loc(node)
        )
        for supertype in supertypes {
            relationships.append(Relationship(
                kind: supertype.isClassInheritance ? .inheritance : .conformance,
                source: qualifiedTypeName, target: supertype.typeRef.name))
        }
        if let body = node.firstChild(withType: "enum_class_body") {
            for child in body.namedChildren() where child.nodeType == "enum_entry" {
                if let enumCase = extractEnumEntry(child) { typeDecl.enumCases.append(enumCase) }
            }
            extractBody(body, into: &typeDecl, skipEnumEntries: true)
        } else if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Type Alias

    func extractTypeAlias(_ node: Node) -> TypeDeclaration? {
        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)
        let modifierInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        let generics = extractTypeParameters(node.firstChild(withType: "type_parameters"))

        var targetType: [TypeReference] = []
        if let userTypeNode = node.firstChild(withType: "user_type") {
            targetType.append(extractTypeReference(userTypeNode))
        } else if let nullableTypeNode = node.firstChild(withType: "nullable_type") {
            targetType.append(extractNullableType(nullableTypeNode))
        }

        return TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName, kind: .typeAlias,
            accessLevel: modifierInfo.accessLevel, genericParameters: generics,
            inheritedTypes: targetType, annotations: modifierInfo.annotations,
            namespace: currentNamespace, location: loc(node)
        )
    }
}
