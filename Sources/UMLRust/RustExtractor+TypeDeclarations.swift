import UMLCore
import UMLTreeSitter

extension RustExtractor {
    mutating func extractStructDeclaration(_ node: Node) -> TypeDeclaration? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)
        let body = node.child(byFieldName: "body")

        return TypeDeclaration(
            id: qualifiedTypeName,
            name: name,
            qualifiedName: qualifiedTypeName,
            kind: .struct,
            accessLevel: accessLevel(for: node, default: .private),
            genericParameters: extractGenericParameters(from: node.child(byFieldName: "type_parameters")),
            members: body.map(extractStructMembers(from:)) ?? [],
            annotations: extractAttributes(from: node),
            namespace: currentNamespace,
            location: loc(node)
        )
    }

    mutating func extractEnumDeclaration(_ node: Node) -> TypeDeclaration? {
        guard let nameNode = node.child(byFieldName: "name"),
              let body = node.child(byFieldName: "body") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)

        return TypeDeclaration(
            id: qualifiedTypeName,
            name: name,
            qualifiedName: qualifiedTypeName,
            kind: .enum,
            accessLevel: accessLevel(for: node, default: .private),
            genericParameters: extractGenericParameters(from: node.child(byFieldName: "type_parameters")),
            enumCases: extractEnumCases(from: body),
            annotations: extractAttributes(from: node),
            namespace: currentNamespace,
            location: loc(node)
        )
    }

    mutating func extractTraitDeclaration(_ node: Node) -> TypeDeclaration? {
        guard let nameNode = node.child(byFieldName: "name"),
              let body = node.child(byFieldName: "body") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)
        let inheritedTypes = extractTraitBounds(from: node.child(byFieldName: "bounds"))
        for inheritedType in inheritedTypes {
            relationships.append(Relationship(kind: .conformance, source: qualifiedTypeName, target: inheritedType.name))
        }

        let associatedTypes = body.namedChildren()
            .filter { $0.nodeType == "associated_type" }
            .compactMap(extractAssociatedType(from:))
        let members = extractTraitMembers(from: body)

        return TypeDeclaration(
            id: qualifiedTypeName,
            name: name,
            qualifiedName: qualifiedTypeName,
            kind: .trait,
            accessLevel: accessLevel(for: node, default: .private),
            genericParameters: extractGenericParameters(from: node.child(byFieldName: "type_parameters")),
            associatedTypes: associatedTypes,
            inheritedTypes: inheritedTypes,
            members: members,
            annotations: extractAttributes(from: node),
            namespace: currentNamespace,
            location: loc(node)
        )
    }

    mutating func extractTypeAliasDeclaration(_ node: Node) -> TypeDeclaration? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)
        return TypeDeclaration(
            id: qualifiedTypeName,
            name: name,
            qualifiedName: qualifiedTypeName,
            kind: .typeAlias,
            accessLevel: accessLevel(for: node, default: .private),
            genericParameters: extractGenericParameters(from: node.child(byFieldName: "type_parameters")),
            annotations: extractAttributes(from: node),
            namespace: currentNamespace,
            location: loc(node)
        )
    }

    mutating func recordImplBlock(_ node: Node) {
        guard let typeNode = node.child(byFieldName: "type"),
              let targetName = implTargetName(from: typeNode) else { return }
        let members = node.child(byFieldName: "body").map { extractImplMembers(from: $0) } ?? []
        if !members.isEmpty {
            pendingImplMembers[targetName, default: []].append(contentsOf: members)
        }
        if let traitNode = node.child(byFieldName: "trait"),
           let traitType = extractTypeReference(traitNode) {
            pendingImplSupertypes[targetName, default: []].append(traitType)
            relationships.append(Relationship(kind: .conformance, source: targetName, target: traitType.name))
        }
    }

    mutating func applyPendingImpls() {
        var declarations = types
        applyPendingImpls(to: &declarations)
        types = declarations
    }

    private mutating func applyPendingImpls(to declarations: inout [TypeDeclaration]) {
        for index in declarations.indices {
            let scope = CallSiteScope(
                knownProperties: buildPropertyMap(from: declarations[index].members),
                knownTypeNames: declaredTypeNames
            )
            for key in implKeys(for: declarations[index]) {
                if let extraMembers = pendingImplMembers.removeValue(forKey: key) {
                    declarations[index].members.append(contentsOf: extraMembers.compactMap {
                        finalizeMember($0, scope: scope)
                    })
                }
                if let supertypes = pendingImplSupertypes.removeValue(forKey: key) {
                    for supertype in supertypes where !declarations[index].inheritedTypes.contains(supertype) {
                        declarations[index].inheritedTypes.append(supertype)
                    }
                }
            }
            applyPendingImpls(to: &declarations[index].nestedTypes)
        }
    }

    private func implKeys(for declaration: TypeDeclaration) -> [String] {
        if declaration.qualifiedName == declaration.name {
            return [declaration.name]
        }
        return [declaration.qualifiedName, declaration.name]
    }
}
