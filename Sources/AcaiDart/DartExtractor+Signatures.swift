import AcaiCore
import AcaiTreeSitter

// MARK: - Method/Function/Constructor/Getter/Setter/Operator Signatures

extension DartExtractor {

    private func wrapPropertyMember(_ member: Member, isStatic: Bool, at node: Node) -> Member {
        var mods = member.modifiers
        if isStatic, !mods.contains(.static) { mods.append(.static) }
        return Member(
            name: member.name, kind: member.kind,
            accessLevel: member.accessLevel, modifiers: mods,
            type: member.type, isComputed: member.isComputed,
            location: loc(node)
        )
    }

    private func resolveMethodSignatureChild(
        _ child: Node, nodeType: String, isStatic: Bool, at node: Node
    ) -> Member? {
        switch nodeType {
        case "constructor_signature":
            return extractConstructorSignature(child, parentName: "").map { member in
                Member(
                    name: member.name, kind: member.kind,
                    accessLevel: accessLevel(for: member.name),
                    modifiers: isStatic ? member.modifiers + [.static] : member.modifiers,
                    type: member.type, parameters: member.parameters, location: loc(node)
                )
            }
        case "getter_signature":
            return extractGetterSignature(child).map { wrapPropertyMember($0, isStatic: isStatic, at: node) }
        case "setter_signature":
            return extractSetterSignature(child).map { wrapPropertyMember($0, isStatic: isStatic, at: node) }
        case "operator_signature":
            return extractOperatorSignature(child)
        default:
            return nil
        }
    }

    func extractMethodSignature(_ node: Node) -> Member? {
        let isStatic = node.hasAnonymousChild("static", in: context)
        var returnType: TypeReference?
        var name = ""
        var parameters: [Parameter] = []
        var genericParams: [GenericParameter] = []

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if let member = resolveMethodSignatureChild(
                child, nodeType: nodeType, isStatic: isStatic, at: node
            ) {
                return member
            }
            if nodeType == "function_signature" {
                let inner = extractFunctionSignatureInner(child)
                returnType = inner.returnType
                name = inner.name
                parameters = inner.parameters
                genericParams = inner.genericParameters
            }
        }

        guard !name.isEmpty else { return nil }
        var modifiers: [Modifier] = []
        if isStatic { modifiers.append(.static) }
        if node.hasAnonymousChild("abstract", in: context) { modifiers.append(.abstract) }

        return Member(
            name: name, kind: .method,
            accessLevel: accessLevel(for: name),
            modifiers: modifiers,
            type: returnType, parameters: parameters,
            genericParameters: genericParams,
            location: loc(node)
        )
    }

    func extractFunctionSignature(_ node: Node) -> Member? {
        let inner = extractFunctionSignatureInner(node)
        guard !inner.name.isEmpty else { return nil }

        var modifiers: [Modifier] = []
        if node.hasAnonymousChild("static", in: context) { modifiers.append(.static) }
        if node.hasAnonymousChild("external", in: context) { modifiers.append(.external) }

        return Member(
            name: inner.name, kind: .method,
            accessLevel: accessLevel(for: inner.name),
            modifiers: modifiers,
            type: inner.returnType, parameters: inner.parameters,
            genericParameters: inner.genericParameters,
            location: loc(node)
        )
    }

    private struct FunctionSignatureInfo {
        var returnType: TypeReference?
        var name: String = ""
        var parameters: [Parameter] = []
        var genericParameters: [GenericParameter] = []
    }

    private func applyFunctionSignatureChild(
        _ child: Node, nodeType: String, to info: inout FunctionSignatureInfo
    ) {
        switch nodeType {
        case "identifier":
            if info.name.isEmpty { info.name = text(child) }
        case "type_parameters":
            info.genericParameters = extractTypeParameterList(child)
        case "formal_parameter_list":
            info.parameters = extractFormalParameterList(child)
        case "type_identifier", "void_type", "function_type":
            if info.returnType == nil {
                info.returnType = extractTypeReference(child)
            }
        default:
            if info.returnType == nil, let ref = extractTypeReference(child) {
                info.returnType = ref
            }
        }
    }

    private func extractFunctionSignatureInner(_ node: Node) -> FunctionSignatureInfo {
        var info = FunctionSignatureInfo()
        if let nameNode = node.child(byFieldName: "name") {
            info.name = text(nameNode)
        }
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            applyFunctionSignatureChild(child, nodeType: nodeType, to: &info)
        }
        return info
    }

    // MARK: - Constructor

    func extractConstructorSignature(_ node: Node, parentName: String) -> Member? {
        var name = parentName
        var parameters: [Parameter] = []

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "identifier":
                let childText = text(child)
                if childText != parentName && !childText.isEmpty {
                    name = childText
                }
            case "formal_parameter_list":
                parameters = extractFormalParameterList(child)
            default:
                break
            }
        }

        var modifiers: [Modifier] = []
        if node.hasAnonymousChild("const", in: context) { modifiers.append(.const) }

        return Member(
            name: name, kind: .initializer,
            accessLevel: accessLevel(for: name),
            modifiers: modifiers,
            parameters: parameters,
            location: loc(node)
        )
    }

    func extractFactoryConstructorSignature(_ node: Node) -> Member? {
        var name = ""
        var parameters: [Parameter] = []

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "identifier":
                if name.isEmpty { name = text(child) }
            case "formal_parameter_list":
                parameters = extractFormalParameterList(child)
            default:
                break
            }
        }

        return Member(
            name: name, kind: .initializer, accessLevel: accessLevel(for: name),
            modifiers: [.factory], parameters: parameters, location: loc(node)
        )
    }

    // MARK: - Getter/Setter/Operator

    func extractGetterSignature(_ node: Node) -> Member? {
        var returnType: TypeReference?
        var name = ""

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "identifier":
                name = text(child)
            case "type_identifier", "void_type":
                returnType = extractTypeReference(child)
            default:
                break
            }
        }
        guard !name.isEmpty else { return nil }

        var modifiers: [Modifier] = []
        if node.hasAnonymousChild("static", in: context) { modifiers.append(.static) }

        return Member(
            name: name, kind: .property,
            accessLevel: accessLevel(for: name),
            modifiers: modifiers,
            type: returnType, isComputed: true,
            location: loc(node)
        )
    }

    func extractSetterSignature(_ node: Node) -> Member? {
        var name = ""
        var paramType: TypeReference?

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "identifier":
                name = text(child)
            case "formal_parameter_list":
                let params = extractFormalParameterList(child)
                paramType = params.first?.type
            default:
                break
            }
        }
        guard !name.isEmpty else { return nil }

        var modifiers: [Modifier] = []
        if node.hasAnonymousChild("static", in: context) { modifiers.append(.static) }

        return Member(
            name: name, kind: .property,
            accessLevel: accessLevel(for: name),
            modifiers: modifiers,
            type: paramType, isComputed: true,
            location: loc(node)
        )
    }

    func extractOperatorSignature(_ node: Node) -> Member? {
        var returnType: TypeReference?
        var operatorName = "operator"
        var parameters: [Parameter] = []

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "type_identifier", "void_type":
                if returnType == nil { returnType = extractTypeReference(child) }
            case "binary_operator", "unary_prefix_operator", "unary_postfix_operator",
                 "tilde_operator", "minus_operator", "negation_operator":
                operatorName = text(child).trimmingCharacters(in: .whitespacesAndNewlines)
            case "formal_parameter_list":
                parameters = extractFormalParameterList(child)
            default:
                break
            }
        }

        return Member(
            name: operatorName, kind: .method, accessLevel: accessLevel(for: operatorName),
            type: returnType, parameters: parameters, location: loc(node)
        )
    }
}
