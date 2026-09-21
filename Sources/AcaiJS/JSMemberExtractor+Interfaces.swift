import AcaiCore
import AcaiTreeSitter

// MARK: - Interface Members, Constructor Parameter Properties & Prototype Members

extension JSMemberExtractor {

    // MARK: - Interface Members (TypeScript)

    func propertySignature(_ node: Node) -> Member {
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { $0.text(in: context) } ?? ""

        var accessLevel: AccessLevel?
        var modifiers: [Modifier] = []

        if let acc = typeReferences.extractAccessibilityModifier(node) {
            accessLevel = acc
        }
        if node.hasDirectChildText("readonly", in: context) {
            modifiers.append(.readonly)
        }

        var propType = typeReferences.extractTypeAnnotation(node)
        if node.hasDirectChildText("?", in: context) {
            propType?.isOptional = true
        }

        return Member(
            name: name, kind: .property,
            accessLevel: accessLevel ?? .internal,
            modifiers: modifiers,
            type: propType,
            location: node.location(in: context)
        )
    }

    func methodSignature(_ node: Node) -> Member {
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { $0.text(in: context) } ?? ""

        let accessLevel = typeReferences.extractAccessibilityModifier(node)
        let generics = typeReferences.extractTypeParameters(node)
        let params: [Parameter]
        if let paramsNode = node.child(byFieldName: "parameters") {
            params = parameterExtractor.parameters(paramsNode)
        } else {
            params = []
        }
        let returnType = typeReferences.extractReturnTypeAnnotation(node)

        return Member(
            name: name, kind: .method,
            accessLevel: accessLevel ?? .internal,
            type: returnType,
            parameters: params,
            genericParameters: generics,
            location: node.location(in: context)
        )
    }

    // MARK: - Constructor Parameter Properties (TypeScript)

    func constructorParameterProperties(_ ctorNode: Node) -> [Member] {
        guard let paramsNode = ctorNode.child(byFieldName: "parameters") else { return [] }
        var members: [Member] = []
        for child in paramsNode.children() {
            guard let childType = child.nodeType else { continue }
            guard childType == "required_parameter" || childType == "optional_parameter" else { continue }

            let accessMod = typeReferences.extractAccessibilityModifier(child)
            let hasReadonly = child.hasDirectChildText("readonly", in: context)
            guard accessMod != nil || hasReadonly else { continue }

            let paramName = parameterExtractor.parameterName(child)
            var modifiers: [Modifier] = []
            if hasReadonly { modifiers.append(.readonly) }

            let paramType = typeReferences.extractTypeAnnotation(child)
            members.append(Member(
                name: paramName,
                kind: .property,
                accessLevel: accessMod ?? .internal,
                modifiers: modifiers,
                type: paramType
            ))
        }
        return members
    }

    // MARK: - Prototype Pattern Members (JS only)

    func prototypeMember(name memberName: String, assignedValue rightNode: Node?) -> Member {
        guard let rightNode, let rightType = rightNode.nodeType, Self.functionNodeTypes.contains(rightType) else {
            return Member(name: memberName, kind: .property, accessLevel: .internal)
        }
        var modifiers: [Modifier] = []
        if rightNode.hasDirectChildText("async", in: context) { modifiers.append(.async) }
        let params = rightNode.child(byFieldName: "parameters").map { parameterExtractor.parameters($0) } ?? []
        return Member(
            name: memberName, kind: .method, accessLevel: .internal, modifiers: modifiers, parameters: params)
    }
}
