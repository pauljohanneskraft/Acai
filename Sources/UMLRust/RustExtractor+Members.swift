import UMLCore
import UMLTreeSitter

extension RustExtractor {
    func extractStructMembers(from body: Node) -> [Member] {
        switch body.nodeType {
        case "field_declaration_list":
            return body.namedChildren().compactMap(extractNamedField(from:))
        case "ordered_field_declaration_list":
            var members: [Member] = []
            var index = 0
            for child in body.namedChildren() {
                guard child.nodeType != "attribute_item",
                      let type = extractTypeReference(child) else { continue }
                members.append(Member(
                    name: "_\(index)",
                    kind: .property,
                    accessLevel: .private,
                    type: type,
                    location: loc(child)
                ))
                index += 1
            }
            return members
        default:
            return []
        }
    }

    func extractEnumCases(from body: Node) -> [EnumCase] {
        body.namedChildren().compactMap { child in
            guard child.nodeType == "enum_variant",
                  let nameNode = child.child(byFieldName: "name") else { return nil }
            let rawValue = child.child(byFieldName: "value").map(text)
            return EnumCase(name: text(nameNode), rawValue: rawValue, location: loc(child))
        }
    }

    func extractTraitMembers(from body: Node) -> [Member] {
        var members: [Member] = []
        let scope = CallSiteScope(knownProperties: [:], knownTypeNames: declaredTypeNames)
        for child in body.namedChildren() {
            switch child.nodeType {
            case "function_signature_item":
                if let member = finalizeMember(
                    extractFunctionSignatureMember(child, defaultAccessLevel: .public, treatNoSelfAsStatic: true),
                    scope: scope
                ) {
                    members.append(member)
                }
            case "function_item":
                if let member = finalizeMember(
                    extractFunctionMember(child, defaultAccessLevel: .public, treatNoSelfAsStatic: true),
                    scope: scope
                ) {
                    members.append(member)
                }
            default:
                break
            }
        }
        return members
    }

    func extractImplMembers(from body: Node) -> [PendingImplMember] {
        body.namedChildren().compactMap { child in
            guard child.nodeType == "function_item" else { return nil }
            return extractFunctionMember(child, defaultAccessLevel: .private, treatNoSelfAsStatic: true)
        }
    }

    func extractNamedField(from node: Node) -> Member? {
        guard node.nodeType == "field_declaration",
              let nameNode = node.child(byFieldName: "name"),
              let typeNode = node.child(byFieldName: "type"),
              let type = extractTypeReference(typeNode) else { return nil }
        return Member(
            name: text(nameNode),
            kind: .property,
            accessLevel: accessLevel(for: node, default: .private),
            type: type,
            annotations: extractAttributes(from: node),
            location: loc(node)
        )
    }

    func extractFunctionMember(
        _ node: Node,
        defaultAccessLevel: AccessLevel,
        treatNoSelfAsStatic: Bool
    ) -> PendingImplMember? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let parameters = node.child(byFieldName: "parameters").map(extractParameters(from:)) ?? ([], false)
        var modifiers = extractFunctionModifiers(from: node)
        if treatNoSelfAsStatic && !parameters.hasSelf {
            modifiers.append(.static)
        }
        let member = Member(
            name: text(nameNode),
            kind: .method,
            accessLevel: accessLevel(for: node, default: defaultAccessLevel),
            modifiers: modifiers,
            type: node.child(byFieldName: "return_type").flatMap(extractTypeReference),
            parameters: parameters.parameters,
            genericParameters: extractGenericParameters(from: node.child(byFieldName: "type_parameters")),
            annotations: extractAttributes(from: node),
            location: loc(node)
        )
        return PendingImplMember(member: member, body: node.child(byFieldName: "body"))
    }

    func extractFunctionSignatureMember(
        _ node: Node,
        defaultAccessLevel: AccessLevel,
        treatNoSelfAsStatic: Bool
    ) -> PendingImplMember? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let parameters = node.child(byFieldName: "parameters").map(extractParameters(from:)) ?? ([], false)
        var modifiers = extractFunctionModifiers(from: node)
        modifiers.append(.abstract)
        if treatNoSelfAsStatic && !parameters.hasSelf {
            modifiers.append(.static)
        }
        let member = Member(
            name: text(nameNode),
            kind: .method,
            accessLevel: accessLevel(for: node, default: defaultAccessLevel),
            modifiers: modifiers,
            type: node.child(byFieldName: "return_type").flatMap(extractTypeReference),
            parameters: parameters.parameters,
            genericParameters: extractGenericParameters(from: node.child(byFieldName: "type_parameters")),
            annotations: extractAttributes(from: node),
            location: loc(node)
        )
        return PendingImplMember(member: member, body: nil)
    }

    func finalizeMember(_ pending: PendingImplMember?, knownProperties: [String: String]) -> Member? {
        guard let pending else { return nil }
        let scope = CallSiteScope(knownProperties: knownProperties, knownTypeNames: declaredTypeNames)
        return finalizeMember(pending, scope: scope)
    }

    func finalizeMember(_ pending: PendingImplMember?, scope: CallSiteScope) -> Member? {
        guard let pending else { return nil }
        var member = pending.member
        member.callSites = extractCallSites(from: pending.body, scope: scope)
        member.assignments = extractAssignments(from: pending.body)
        member.referencedTypeNames = referencedTypeNames(in: pending.body)
        return member
    }

    func extractParameters(from node: Node) -> (parameters: [Parameter], hasSelf: Bool) {
        var parameters: [Parameter] = []
        var hasSelf = false
        for child in node.namedChildren() {
            switch child.nodeType {
            case "self_parameter":
                hasSelf = true
            case "parameter":
                if let parameter = extractParameter(from: child) {
                    parameters.append(parameter)
                }
            case "variadic_parameter":
                if let parameter = extractParameter(from: child, isVariadic: true) {
                    parameters.append(parameter)
                }
            default:
                break
            }
        }
        return (parameters, hasSelf)
    }

    func extractParameter(from node: Node, isVariadic: Bool = false) -> Parameter? {
        let patternText = node.child(byFieldName: "pattern").map(text) ?? text(node)
        guard let name = parameterName(from: patternText) else { return nil }
        return Parameter(
            internalName: name,
            type: node.child(byFieldName: "type").flatMap(extractTypeReference),
            isVariadic: isVariadic
        )
    }

    func extractFunctionModifiers(from node: Node) -> [Modifier] {
        var modifiers: [Modifier] = []
        if hasDirectChildText("async", in: node) {
            modifiers.append(.async)
        }
        if hasDirectChildText("const", in: node) {
            modifiers.append(.const)
        }
        if hasDirectChildText("unsafe", in: node) {
            modifiers.append(.synchronized)
        }
        return modifiers
    }

    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        guard node.nodeType == "call_expression",
              let function = node.child(byFieldName: "function") else { return nil }

        if function.nodeType == "field_expression",
           let receiver = function.child(byFieldName: "value"),
           let field = function.child(byFieldName: "field") {
            return resolveMemberCall(
                receiver: receiver,
                methodName: text(field),
                grammar: MemberCallGrammar(selfNodeType: "self", memberAccessType: "field_expression", memberField: "field"),
                scope: scope,
                location: loc(node)
            )
        }

        if (function.nodeType == "scoped_identifier" || function.nodeType == "scoped_type_identifier"),
           let path = function.child(byFieldName: "path"),
           let nameNode = function.child(byFieldName: "name") {
            return scope.resolvedCallSite(
                receiverName: simpleTypeName(from: text(path)),
                methodName: text(nameNode),
                location: loc(node)
            )
        }

        return nil
    }

    func resolveAssignment(_ node: Node) -> VariableAssignment? {
        guard node.nodeType == "assignment_expression" || node.nodeType == "compound_assignment_expr",
              let left = node.child(byFieldName: "left"),
              let right = node.child(byFieldName: "right"),
              let target = parseAssignmentTarget(text(left)) else { return nil }

        return VariableAssignment(
            targetName: target.name,
            targetReceiver: target.receiver,
            op: node.nodeType == "assignment_expression" ? .assign : .compound,
            value: classifyAssignmentValue(right),
            location: loc(node)
        )
    }

    func classifyAssignmentValue(_ node: Node) -> VariableAssignment.Value {
        let literalTypes = LiteralNodeTypes(
            numeric: ["integer_literal", "float_literal"],
            string: ["string_literal", "char_literal"]
        )
        if let literal = classifyLiteral(node, literalTypes) {
            return literal
        }

        let trimmed = trimmedText(node)
        if trimmed == "true" || trimmed == "false" {
            return .init(kind: .booleanLiteral, text: trimmed)
        }
        if let enumCase = enumCaseValue(fromScopedText: trimmed) {
            return enumCase
        }
        return .init(kind: .expression, text: expressionSnippet(node))
    }

    func enumCaseValue(fromScopedText rawText: String) -> VariableAssignment.Value? {
        let parts = rawText.components(separatedBy: "::")
        guard parts.count == 2,
              let receiver = parts.first,
              let caseName = parts.last,
              receiver.first?.isUppercase == true else { return nil }
        return VariableAssignment.Value(kind: .enumCase, text: caseName, receiverTypeName: receiver)
    }
}
