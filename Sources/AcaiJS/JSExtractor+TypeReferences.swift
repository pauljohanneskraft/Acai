import AcaiCore
import AcaiTreeSitter

// MARK: - Parameters, Types & Utilities

extension JSExtractor {

    // MARK: - Call Site Extraction

    /// Matches JS/TS `call_expression { function: member_expression { object, property } }`.
    ///
    /// Handles:
    /// - `receiver.method(args)` — `object` is an `identifier` (a known property or type),
    /// - `this.receiver.method(args)` — `object` is a `member_expression` whose own `object` is `this`,
    /// - `this.method(args)` — `object` is a `this` node (a call on the enclosing instance),
    /// - `TypeName.method(args)` — `object` is a known type (static call).
    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        guard node.nodeType == "call_expression",
              let funcNode = node.child(byFieldName: "function")
        else { return nil }

        // Bare `foo()` — no receiver. JS has no implicit `this`, so this is a free/imported function.
        if funcNode.nodeType == "identifier" {
            return scope.bareCall(named: text(funcNode), implicitSelf: false, location: loc(node))
        }

        guard funcNode.nodeType == "member_expression",
              let propertyNode = funcNode.child(byFieldName: "property"),
              let objectNode   = funcNode.child(byFieldName: "object")
        else { return nil }

        return resolveMemberCall(
            receiver: objectNode,
            methodName: text(propertyNode),
            grammar: MemberCallGrammar(
                selfNodeType: "this", memberAccessType: "member_expression", memberField: "property"
            ),
            scope: scope,
            location: loc(node)
        )
    }

    /// Provable local-variable types: a TypeScript annotation (`const x: Foo`), a `new Foo()`
    /// construction, or a same-type method call with an unambiguous return type (`const x =
    /// compute()`, via `scope.knownMethodReturnTypes`), so `x.method()` resolves to `Foo` (RC4/RC-I).
    func localBindings(in body: Node, scope: CallSiteScope) -> [String: String] {
        collectLocalBindings(in: body) { node in
            guard node.nodeType == "variable_declarator",
                  let nameNode = node.child(byFieldName: "name"), nameNode.nodeType == "identifier"
            else { return nil }
            let name = text(nameNode)
            if let typeAnnotation = node.child(byFieldName: "type"),
               let typeId = typeAnnotation.firstChild(withType: "type_identifier") {
                return (name, text(typeId))
            }
            guard let value = node.child(byFieldName: "value") else { return nil }
            if value.nodeType == "new_expression",
               let ctor = value.child(byFieldName: "constructor"), ctor.nodeType == "identifier" {
                return (name, text(ctor))
            }
            if value.nodeType == "call_expression",
               let callee = value.child(byFieldName: "function"), callee.nodeType == "identifier",
               let returnType = scope.knownMethodReturnTypes[text(callee)] {
                return (name, returnType)
            }
            return nil
        }
    }

    // MARK: - Parameters

    func extractParameters(_ node: Node) -> [Parameter] {
        var params: [Parameter] = []
        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            switch childType {
            case "formal_parameter", "required_parameter", "optional_parameter":
                params.append(extractSingleParameter(child, isOptional: childType == "optional_parameter"))
            case "rest_pattern", "rest_element":
                var param = extractRestParameter(child)
                param.isVariadic = true
                params.append(param)
            case "identifier":
                params.append(Parameter(internalName: text(child)))
            case "assignment_pattern":
                params.append(extractAssignmentParameter(child))
            case "destructuring_pattern", "array_pattern", "object_pattern":
                params.append(Parameter(internalName: text(child)))
            default:
                break
            }
        }
        return params
    }

    private func extractSingleParameter(_ node: Node, isOptional: Bool) -> Parameter {
        let name: String
        if let patternNode = node.child(byFieldName: "pattern") {
            name = text(patternNode)
        } else {
            name = extractParameterName(node)
        }

        var paramType: TypeReference?
        if isTypeScript {
            paramType = extractTypeAnnotation(node)
        }

        if isOptional { paramType?.isOptional = true }

        let defaultValue: String? = node.child(byFieldName: "value").map { text($0) }

        var modifiers: [Modifier] = []
        if node.hasDirectChildText("readonly", in: context) {
            modifiers.append(.readonly)
        }

        return Parameter(internalName: name, type: paramType, defaultValue: defaultValue, modifiers: modifiers)
    }

    private func extractRestParameter(_ node: Node) -> Parameter {
        var name = ""
        for child in node.namedChildren() where child.nodeType == "identifier" {
            name = text(child)
            break
        }
        if name.isEmpty {
            if let patternNode = node.child(byFieldName: "pattern") {
                name = text(patternNode)
            } else {
                name = text(node).replacingOccurrences(of: "...", with: "")
            }
        }

        var paramType: TypeReference?
        if isTypeScript { paramType = extractTypeAnnotation(node) }

        return Parameter(internalName: name, type: paramType, isVariadic: true)
    }

    private func extractAssignmentParameter(_ node: Node) -> Parameter {
        let name = node.child(byFieldName: "left").map { text($0) } ?? ""
        let defaultValue = node.child(byFieldName: "right").map { text($0) }
        return Parameter(internalName: name, defaultValue: defaultValue)
    }

    func extractParameterName(_ node: Node) -> String {
        if let pattern = node.child(byFieldName: "pattern") {
            return text(pattern)
        }
        for child in node.children() where child.nodeType == "identifier" {
            return text(child)
        }
        return ""
    }

    // MARK: - Type Annotations (TypeScript)

    func extractTypeAnnotation(_ node: Node) -> TypeReference? {
        guard isTypeScript else { return nil }
        guard let typeAnnotation = node.firstChild(withType: "type_annotation") else { return nil }
        if let typeNode = typeAnnotation.namedChildren().first {
            return extractTypeReference(typeNode)
        }
        return nil
    }

    func extractReturnTypeAnnotation(_ node: Node) -> TypeReference? {
        guard isTypeScript else { return nil }
        if let returnType = node.child(byFieldName: "return_type") {
            if let typeNode = returnType.namedChildren().first {
                return extractTypeReference(typeNode)
            }
            return extractTypeReference(returnType)
        }
        return extractTypeAnnotation(node)
    }

    // MARK: - Type Reference Extraction

    private static let passthroughNodeTypes: Set<String> = [
        "predefined_type", "type_identifier", "identifier",
        "union_type", "intersection_type", "function_type", "literal_type",
        "tuple_type", "conditional_type", "index_type_query", "mapped_type",
        "type_query", "object_type", "template_literal_type", "existential_type",
        "nested_type_identifier", "member_expression", "this_type"
    ]

    private func extractTypeReference(_ node: Node) -> TypeReference {
        guard let nodeType = node.nodeType else {
            return TypeReference(name: text(node))
        }

        if Self.passthroughNodeTypes.contains(nodeType) {
            return TypeReference(name: text(node))
        }

        switch nodeType {
        case "generic_type":
            return extractGenericTypeReference(node)
        case "array_type":
            return extractArrayTypeReference(node)
        case "parenthesized_type", "readonly_type":
            return extractWrappedTypeReference(node)
        case "flow_maybe_type":
            return extractOptionalTypeReference(node)
        default:
            return TypeReference(name: text(node))
        }
    }

    private func extractGenericTypeReference(_ node: Node) -> TypeReference {
        let nameNode = node.child(byFieldName: "name") ?? node.namedChildren().first
        let name = nameNode.map { text($0) } ?? text(node)
        var genericArgs: [TypeReference] = []
        if let typeArgs = node.child(byFieldName: "type_arguments")
            ?? node.firstChild(withType: "type_arguments") {
            genericArgs = typeArgs.namedChildren().map { extractTypeReference($0) }
        }
        return TypeReference(name: name, genericArguments: genericArgs)
    }

    private func extractArrayTypeReference(_ node: Node) -> TypeReference {
        guard let elementType = node.namedChildren().first else {
            return TypeReference(name: text(node), isArray: true)
        }
        let inner = extractTypeReference(elementType)
        return TypeReference(name: inner.name, genericArguments: inner.genericArguments, isArray: true)
    }

    private func extractWrappedTypeReference(_ node: Node) -> TypeReference {
        if let inner = node.namedChildren().first { return extractTypeReference(inner) }
        return TypeReference(name: text(node))
    }

    private func extractOptionalTypeReference(_ node: Node) -> TypeReference {
        guard let inner = node.namedChildren().first else {
            return TypeReference(name: text(node), isOptional: true)
        }
        var ref = extractTypeReference(inner)
        ref.isOptional = true
        return ref
    }

    func extractTypeReferenceFromExpression(_ node: Node) -> TypeReference {
        switch node.nodeType ?? "" {
        case "identifier", "type_identifier", "property_identifier":
            return TypeReference(name: text(node))
        case "generic_type":
            return extractTypeReference(node)
        default:
            return TypeReference(name: text(node))
        }
    }

    // MARK: - Generic / Type Parameters

    func extractTypeParameters(_ node: Node) -> [GenericParameter] {
        guard let typeParamsNode = node.child(byFieldName: "type_parameters")
                ?? node.firstChild(withType: "type_parameters") else {
            return []
        }

        var params: [GenericParameter] = []
        for child in typeParamsNode.namedChildren() {
            guard child.nodeType == "type_parameter" else { continue }
            let nameNode = child.child(byFieldName: "name") ?? child.namedChildren().first
            let name = nameNode.map { text($0) } ?? ""
            guard !name.isEmpty else { continue }

            var constraints: [GenericConstraint] = []
            if let constraintNode = child.child(byFieldName: "constraint") {
                let constraintType = extractTypeReference(constraintNode)
                constraints.append(GenericConstraint(kind: .conformance, type: constraintType))
            }
            params.append(GenericParameter(name: name, constraints: constraints))
        }
        return params
    }

    // MARK: - Accessibility Modifier

    private static let accessLevelMap: [String: AccessLevel] = [
        "public": .public, "private": .private, "protected": .protected
    ]

    func extractAccessibilityModifier(_ node: Node) -> AccessLevel? {
        for child in node.children() where child.nodeType == "accessibility_modifier" {
            if let level = Self.accessLevelMap[text(child)] { return level }
        }
        for child in node.children() where child.nodeType != "type_identifier" {
            if let level = Self.accessLevelMap[text(child)] { return level }
        }
        return nil
    }

    // MARK: - Prototype Pattern Detection (JS only)

    private static let functionNodeTypes: Set<String> = [
        "function_expression", "function", "arrow_function"
    ]

    mutating func detectPrototypePatterns(_ root: Node) {
        let assignments = collectPrototypeAssignments(root)
        for assignment in assignments {
            applyPrototypeAssignment(assignment)
        }
    }

    private func collectPrototypeAssignments(
        _ root: Node
    ) -> [(className: String, memberName: String, node: Node)] {
        var results: [(className: String, memberName: String, node: Node)] = []
        for child in root.children() {
            guard child.nodeType == "expression_statement",
                  let expr = child.namedChildren().first,
                  expr.nodeType == "assignment_expression",
                  let leftNode = expr.child(byFieldName: "left"),
                  leftNode.nodeType == "member_expression" else { continue }
            let leftText = text(leftNode)
            guard let protoRange = leftText.range(of: ".prototype.") else { continue }
            let className = String(leftText[leftText.startIndex..<protoRange.lowerBound])
            let memberName = String(leftText[protoRange.upperBound...])
            if !className.isEmpty, !memberName.isEmpty {
                results.append((className, memberName, expr))
            }
        }
        return results
    }

    private mutating func applyPrototypeAssignment(
        _ assignment: (className: String, memberName: String, node: Node)
    ) {
        ensureTypeExists(name: assignment.className)
        let member = buildPrototypeMember(assignment)
        guard let index = types.firstIndex(where: { $0.name == assignment.className }) else { return }
        types[index].members.append(member)
    }

    private func buildPrototypeMember(
        _ assignment: (className: String, memberName: String, node: Node)
    ) -> Member {
        guard let rightNode = assignment.node.child(byFieldName: "right"),
              let rightType = rightNode.nodeType,
              Self.functionNodeTypes.contains(rightType) else {
            return Member(name: assignment.memberName, kind: .property, accessLevel: .internal)
        }
        var modifiers: [Modifier] = []
        if rightNode.hasDirectChildText("async", in: context) { modifiers.append(.async) }
        let params = rightNode.child(byFieldName: "parameters").map { extractParameters($0) } ?? []
        return Member(
            name: assignment.memberName, kind: .method, accessLevel: .internal,
            modifiers: modifiers, parameters: params)
    }

    private mutating func ensureTypeExists(name: String) {
        if !types.contains(where: { $0.name == name }) {
            types.append(
                TypeDeclaration(id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .internal))
        }
    }
}
