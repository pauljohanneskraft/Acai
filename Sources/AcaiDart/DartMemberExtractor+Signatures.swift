import AcaiCore
import AcaiTreeSitter

// MARK: - Method/Function/Constructor/Getter/Setter/Operator Signatures

extension DartMemberExtractor {

    /// The member a class-body signature node declares, or `nil` when `nodeType` isn't a signature.
    func member(fromSignature node: Node, nodeType: String, parentName: String) -> Member? {
        switch nodeType {
        case "method_signature":
            return methodSignature(node)
        case "function_signature":
            return functionSignature(node)
        case "constructor_signature", "constant_constructor_signature":
            return constructorSignature(node, parentName: parentName)
        case "factory_constructor_signature", "redirecting_factory_constructor_signature":
            return factoryConstructorSignature(node)
        case "getter_signature":
            return getterSignature(node)
        case "setter_signature":
            return setterSignature(node)
        case "operator_signature":
            return operatorSignature(node)
        default:
            return nil
        }
    }

    private func wrapPropertyMember(_ member: Member, isStatic: Bool, at node: Node) -> Member {
        var mods = member.modifiers
        if isStatic, !mods.contains(.static) { mods.append(.static) }
        return Member(
            name: member.name, kind: member.kind,
            accessLevel: member.accessLevel, modifiers: mods,
            type: member.type, isComputed: member.isComputed,
            location: node.location(in: context)
        )
    }

    private func resolveMethodSignatureChild(
        _ child: Node, nodeType: String, isStatic: Bool, at node: Node
    ) -> Member? {
        switch nodeType {
        case "constructor_signature":
            return constructorSignature(child, parentName: "").map { member in
                Member(
                    name: member.name, kind: member.kind,
                    accessLevel: DartName(member.name).accessLevel,
                    modifiers: isStatic ? member.modifiers + [.static] : member.modifiers,
                    type: member.type, parameters: member.parameters, location: node.location(in: context)
                )
            }
        case "getter_signature":
            return getterSignature(child).map { wrapPropertyMember($0, isStatic: isStatic, at: node) }
        case "setter_signature":
            return setterSignature(child).map { wrapPropertyMember($0, isStatic: isStatic, at: node) }
        case "operator_signature":
            return operatorSignature(child)
        default:
            return nil
        }
    }

    func methodSignature(_ node: Node) -> Member? {
        let isStatic = node.hasAnonymousChild("static", in: context)
        var returnType: TypeReference?
        var name = ""
        var parameters: [Parameter] = []
        var genericParams: [GenericParameter] = []

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if let member = resolveMethodSignatureChild(child, nodeType: nodeType, isStatic: isStatic, at: node) {
                return member
            }
            if nodeType == "function_signature" {
                let inner = functionSignatureInfo(child)
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
            accessLevel: DartName(name).accessLevel,
            modifiers: modifiers,
            type: returnType, parameters: parameters,
            genericParameters: genericParams,
            location: node.location(in: context)
        )
    }

    func functionSignature(_ node: Node) -> Member? {
        let inner = functionSignatureInfo(node)
        guard !inner.name.isEmpty else { return nil }

        var modifiers: [Modifier] = []
        if node.hasAnonymousChild("static", in: context) { modifiers.append(.static) }
        if node.hasAnonymousChild("external", in: context) { modifiers.append(.external) }

        return Member(
            name: inner.name, kind: .method,
            accessLevel: DartName(inner.name).accessLevel,
            modifiers: modifiers,
            type: inner.returnType, parameters: inner.parameters,
            genericParameters: inner.genericParameters,
            location: node.location(in: context)
        )
    }

    private struct FunctionSignatureInfo {
        var returnType: TypeReference?
        var name: String = ""
        var parameters: [Parameter] = []
        var genericParameters: [GenericParameter] = []
    }

    private func apply(_ child: Node, nodeType: String, to info: inout FunctionSignatureInfo) {
        switch nodeType {
        case "identifier":
            if info.name.isEmpty { info.name = child.text(in: context) }
        case "type_parameters":
            info.genericParameters = typeReferences.typeParameterList(child)
        case "formal_parameter_list":
            info.parameters = parameterExtractor.parameters(child)
        case "type_identifier", "void_type", "function_type":
            if info.returnType == nil {
                info.returnType = typeReferences.typeReference(child)
            }
        default:
            if info.returnType == nil, let ref = typeReferences.typeReference(child) {
                info.returnType = ref
            }
        }
    }

    private func functionSignatureInfo(_ node: Node) -> FunctionSignatureInfo {
        var info = FunctionSignatureInfo()
        if let nameNode = node.child(byFieldName: "name") {
            info.name = nameNode.text(in: context)
        }
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            apply(child, nodeType: nodeType, to: &info)
        }
        return info
    }

    // MARK: - Constructor

    func constructorSignature(_ node: Node, parentName: String) -> Member? {
        var name = parentName
        var parameters: [Parameter] = []

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "identifier":
                let childText = child.text(in: context)
                if childText != parentName && !childText.isEmpty {
                    name = childText
                }
            case "formal_parameter_list":
                parameters = parameterExtractor.parameters(child)
            default:
                break
            }
        }

        var modifiers: [Modifier] = []
        if node.hasAnonymousChild("const", in: context) { modifiers.append(.const) }

        return Member(
            name: name, kind: .initializer,
            accessLevel: DartName(name).accessLevel,
            modifiers: modifiers,
            parameters: parameters,
            location: node.location(in: context)
        )
    }

    func factoryConstructorSignature(_ node: Node) -> Member? {
        var name = ""
        var parameters: [Parameter] = []

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "identifier":
                if name.isEmpty { name = child.text(in: context) }
            case "formal_parameter_list":
                parameters = parameterExtractor.parameters(child)
            default:
                break
            }
        }

        return Member(
            name: name, kind: .initializer, accessLevel: DartName(name).accessLevel,
            modifiers: [.factory], parameters: parameters, location: node.location(in: context)
        )
    }

    // MARK: - Getter/Setter/Operator

    func getterSignature(_ node: Node) -> Member? {
        var returnType: TypeReference?
        var name = ""

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "identifier":
                name = child.text(in: context)
            case "type_identifier", "void_type":
                returnType = typeReferences.typeReference(child)
            default:
                break
            }
        }
        guard !name.isEmpty else { return nil }

        var modifiers: [Modifier] = []
        if node.hasAnonymousChild("static", in: context) { modifiers.append(.static) }

        return Member(
            name: name, kind: .property,
            accessLevel: DartName(name).accessLevel,
            modifiers: modifiers,
            type: returnType, isComputed: true,
            location: node.location(in: context)
        )
    }

    func setterSignature(_ node: Node) -> Member? {
        var name = ""
        var paramType: TypeReference?

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "identifier":
                name = child.text(in: context)
            case "formal_parameter_list":
                paramType = parameterExtractor.parameters(child).first?.type
            default:
                break
            }
        }
        guard !name.isEmpty else { return nil }

        var modifiers: [Modifier] = []
        if node.hasAnonymousChild("static", in: context) { modifiers.append(.static) }

        return Member(
            name: name, kind: .property,
            accessLevel: DartName(name).accessLevel,
            modifiers: modifiers,
            type: paramType, isComputed: true,
            location: node.location(in: context)
        )
    }

    func operatorSignature(_ node: Node) -> Member? {
        var returnType: TypeReference?
        var operatorName = "operator"
        var parameters: [Parameter] = []

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "type_identifier", "void_type":
                if returnType == nil { returnType = typeReferences.typeReference(child) }
            case "binary_operator", "unary_prefix_operator", "unary_postfix_operator",
                 "tilde_operator", "minus_operator", "negation_operator":
                operatorName = child.text(in: context).trimmingCharacters(in: .whitespacesAndNewlines)
            case "formal_parameter_list":
                parameters = parameterExtractor.parameters(child)
            default:
                break
            }
        }

        return Member(
            name: operatorName, kind: .method, accessLevel: DartName(operatorName).accessLevel,
            type: returnType, parameters: parameters, location: node.location(in: context)
        )
    }
}
