import AcaiCore
import AcaiTreeSitter

// MARK: - Body & Member Extraction

extension KotlinExtractor {

    // MARK: - Body Extraction

    /// Extracts members, nested types, and companion objects from a class/interface/object body.
    /// Used for both `class_body` and `enum_class_body` nodes.
    mutating func extractBody(
        _ node: Node,
        into typeDecl: inout TypeDeclaration,
        skipEnumEntries: Bool = false
    ) {
        // Parent type's qualified ID as namespace, so nested types get correctly-qualified IDs.
        let outerNamespace = declarations.enter(namespace: typeDecl.id)
        defer { declarations.leave(outerNamespace) }

        // Pre-scan: build property → type map for call-site resolution.
        var knownProperties = MemberIndex(members: typeDecl.members).propertyTypes
        for child in node.namedChildren()
            where child.nodeType == "property_declaration" {
            let prop = extractPropertyDeclaration(child)
            if !prop.modifiers.contains(.static),
               let typeName = prop.type?.name {
                knownProperties[prop.name] = typeName
            }
        }

        // Pre-scan: build methodName → returnType map (unambiguous overloads only), so a same-type
        // method call, including one declared later in the type, can seed a local's type.
        var returnTypes = UnambiguousTypeNames()
        for child in node.namedChildren() where child.nodeType == "function_declaration" {
            guard let nameNode = child.firstChild(withType: "simple_identifier"),
                  let returnTypeNode = findReturnType(in: child)
            else { continue }
            let returnType = extractTypeReferenceFromAny(returnTypeNode)
            guard returnType.name != "Unit" else { continue }
            returnTypes.record(returnType.name, for: nameNode.text(in: context))
        }
        let knownMethodReturnTypes = returnTypes.resolved

        let scope = CallSiteScope(
            knownProperties: knownProperties,
            knownTypeNames: declarations.declaredTypeNames,
            knownMethodReturnTypes: knownMethodReturnTypes
        )

        let namedChildren = node.namedChildren()
        var bodyContext = BodyChildContext(
            siblings: namedChildren,
            typeDecl: typeDecl,
            scope: scope,
            skipEnumEntries: skipEnumEntries
        )
        for (index, child) in namedChildren.enumerated() {
            handleBodyChild(child, at: index, context: &bodyContext)
        }
        typeDecl = bodyContext.typeDecl
    }

    private struct BodyChildContext {
        let siblings: [Node]
        var typeDecl: TypeDeclaration
        let scope: CallSiteScope
        let skipEnumEntries: Bool
    }

    private mutating func handleBodyChild(
        _ child: Node,
        at index: Int,
        context: inout BodyChildContext
    ) {
        switch child.nodeType {
        case "enum_entry" where context.skipEnumEntries:
            return
        case "function_declaration":
            context.typeDecl.members.append(
                extractFunctionDeclaration(
                    child, scope: context.scope
                )
            )
        case "property_declaration":
            let hasGetterOrSetter = nextSiblingIsAccessor(
                at: index, in: context.siblings
            )
            context.typeDecl.members.append(
                extractPropertyDeclaration(
                    child, isComputed: hasGetterOrSetter, scope: context.scope
                )
            )
        case "anonymous_initializer":
            // An `init { … }` block — Kotlin's real constructor body. Record its calls on an
            // `.initializer` member so they're never a dead-code false positive.
            context.typeDecl.members.append(extractAnonymousInitializer(child, scope: context.scope))
        case "secondary_constructor":
            context.typeDecl.members.append(
                extractSecondaryConstructor(
                    child,
                    scope: context.scope
                )
            )
        case "companion_object", "class_declaration", "object_declaration":
            handleNestedTypeChild(child, into: &context.typeDecl)
        default:
            break
        }
    }

    private mutating func handleNestedTypeChild(_ child: Node, into typeDecl: inout TypeDeclaration) {
        switch child.nodeType {
        case "companion_object":
            if let obj = extractCompanionObject(child) { typeDecl.nestedTypes.append(obj) }
        case "object_declaration":
            if let nestedType = extractObjectDeclaration(child) { typeDecl.nestedTypes.append(nestedType) }
        default:
            handleNestedClassDeclaration(child, into: &typeDecl)
        }
    }

    private func nextSiblingIsAccessor(
        at index: Int, in siblings: [Node]
    ) -> Bool {
        let next = index + 1
        guard next < siblings.count else { return false }
        let sibling = siblings[next].nodeType
        return sibling == "getter" || sibling == "setter"
    }

    private mutating func handleNestedClassDeclaration(
        _ child: Node, into typeDecl: inout TypeDeclaration
    ) {
        if child.hasDirectChildText("interface", in: context) {
            if let nestedType = extractInterfaceDeclaration(child) {
                typeDecl.nestedTypes.append(nestedType)
            }
        } else if let nestedType = extractClassDeclaration(child) {
            typeDecl.nestedTypes.append(nestedType)
        }
    }

    // MARK: - Enum Entry

    func extractEnumEntry(_ node: Node) -> EnumCase? {
        guard let nameNode = node.firstChild(withType: "simple_identifier") else { return nil }
        let name = nameNode.text(in: context)
        var rawValue: String?
        if let valueArgs = node.firstChild(withType: "value_arguments") {
            let argsText = valueArgs.text(in: context).trimmingCharacters(in: .whitespaces)
            rawValue = (argsText.hasPrefix("(") && argsText.hasSuffix(")"))
                ? String(argsText.dropFirst().dropLast()) : argsText
        }
        return EnumCase(name: name, rawValue: rawValue, location: node.location(in: context))
    }

    // MARK: - Function Declaration

    mutating func extractFunctionDeclaration(
        _ node: Node,
        scope: CallSiteScope = CallSiteScope()
    ) -> Member {
        let modifierInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        let name = node.firstChild(withType: "simple_identifier").map { $0.text(in: context) } ?? "_anonymous"
        let generics = extractTypeParameters(node.firstChild(withType: "type_parameters"))

        // Extension function receiver (e.g. `fun String.hello() {}`)
        if let receiverRef = extractReceiverType(node) {
            declarations.relationships.append(
                Relationship(kind: .extension, source: name, target: receiverRef.name)
            )
        }

        let params = extractFunctionValueParameters(
            node.firstChild(withType: "function_value_parameters")
        )
        let returnType: TypeReference? = {
            guard let returnTypeNode = findReturnType(in: node) else { return nil }
            let ref = extractTypeReferenceFromAny(returnTypeNode)
            return ref.name == "Unit" ? nil : ref
        }()

        let body = node.firstChild(withType: "function_body")

        return Member(
            name: name, kind: .method,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            type: returnType, parameters: params,
            genericParameters: generics, annotations: modifierInfo.annotations,
            location: node.location(in: context),
            callSites: callSites.callSites(in: body, scope: scope.merging(parameters: params)),
            assignments: assignments.assignments(in: body),
            fieldReads: fieldReads.reads(in: body, scope: scope),
            referencedTypeNames: body?.referencedTypeNames(in: context) ?? [],
            cyclomaticComplexity: body?.cyclomaticComplexity(branchKinds: Self.branchNodeKinds)
        )
    }

    /// Extracts the receiver type from a Kotlin extension function declaration. In `fun
    /// String.hello() {}`, `String` is the receiver type: the AST places it as a type node child
    /// followed by an anonymous `"."` child before the function name.
    private func extractReceiverType(_ node: Node) -> TypeReference? {
        let children = node.children()
        guard let funIndex = children.firstIndex(where: {
            !$0.isNamed && $0.text(in: context) == "fun"
        }) else { return nil }
        var childIndex = children.index(after: funIndex)
        while childIndex < children.endIndex {
            let child = children[childIndex]
            // Skip generics before the receiver.
            if child.nodeType == "type_parameters" {
                childIndex = children.index(after: childIndex)
                continue
            }
            // A type node followed by "." indicates a receiver type.
            if child.isNamed,
               let nodeType = child.nodeType,
               ["user_type", "nullable_type", "parenthesized_type"].contains(nodeType) {
                let nextIndex = children.index(after: childIndex)
                if nextIndex < children.endIndex,
                   !children[nextIndex].isNamed,
                   children[nextIndex].text(in: context) == "." {
                    return extractTypeReferenceFromAny(child)
                }
            }
            break // Not an extension function.
        }
        return nil
    }

    private func findReturnType(in node: Node) -> Node? {
        var foundParams = false
        var foundColon = false
        for child in node.children() {
            let childType = child.nodeType
            if childType == "function_value_parameters" {
                foundParams = true
                continue
            }
            if foundParams && !child.isNamed && child.text(in: context) == ":" {
                foundColon = true
                continue
            }
            if foundColon && child.isNamed {
                let typeNodeTypes = [
                    "user_type", "nullable_type",
                    "function_type", "parenthesized_type"
                ]
                if let childType, typeNodeTypes.contains(childType) { return child }
                break
            }
            if childType == "function_body" { break }
        }
        return nil
    }

    // MARK: - Property Declaration

    func extractPropertyDeclaration(
        _ node: Node,
        isComputed: Bool = false,
        scope: CallSiteScope = CallSiteScope()
    ) -> Member {
        let modifierInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        let isVal = bindingKind(of: node) == "val"
        var modifiers = modifierInfo.modifiers
        if isVal { modifiers.append(.readonly) }

        var name = ""
        var typeRef: TypeReference?

        if let varDecl = node.firstChild(withType: "variable_declaration") {
            name = varDecl.firstChild(withType: "simple_identifier").map { $0.text(in: context) } ?? ""
            typeRef = extractFirstTypeRef(from: varDecl)
        } else {
            name = node.firstChild(withType: "simple_identifier").map { $0.text(in: context) } ?? ""
            typeRef = extractFirstTypeRef(from: node)
        }
        // No explicit `: Type` annotation — infer from a direct construction initializer (`val helper
        // = Helper()`), same heuristic `localBindings` applies to locals. Without this, calls through
        // a composed collaborator field (`helper.doThing()`) can't resolve.
        if typeRef == nil, let constructed = constructedTypeRef(from: propertyInitializerNode(of: node)) {
            typeRef = constructed
        }

        // A custom accessor (`get()`/`set()`) nests as a child; walk each so accessor-only calls
        // aren't lost, and treat the property as computed.
        let accessors = node.namedChildren().filter { $0.nodeType == "getter" || $0.nodeType == "setter" }
        var propertyCallSites = callSites.callSites(in: propertyInitializerNode(of: node), scope: scope)
        for accessor in accessors {
            propertyCallSites += callSites.callSites(in: accessor, scope: scope)
        }

        return Member(
            name: name, kind: .property,
            accessLevel: modifierInfo.accessLevel, modifiers: modifiers,
            type: typeRef,
            isComputed: isComputed || !accessors.isEmpty,
            annotations: modifierInfo.annotations, location: node.location(in: context),
            callSites: propertyCallSites,
            initialValue: propertyInitializerValue(of: node),
            referencedTypeNames: propertyInitializerNode(of: node)?.referencedTypeNames(in: context) ?? []
        )
    }

    /// Records an `init { … }` block's calls on an `.initializer` member (Kotlin's constructor body),
    /// so calls made only during construction aren't lost.
    func extractAnonymousInitializer(_ node: Node, scope: CallSiteScope) -> Member {
        Member(
            name: "init", kind: .initializer, accessLevel: .internal,
            location: node.location(in: context),
            callSites: callSites.callSites(in: node, scope: scope)
        )
    }

    /// The property's initializer expression node (the node after the anonymous `=`), if present.
    private func propertyInitializerNode(of node: Node) -> Node? {
        var foundEq = false
        for child in node.children() {
            if !child.isNamed && child.text(in: context) == "=" {
                foundEq = true
                continue
            }
            if foundEq { return child }
        }
        return nil
    }

    /// Classifies the property's initializer expression (the node after the anonymous `=` token). The
    /// expression may itself be an anonymous token (`null`), so namedness isn't required.
    private func propertyInitializerValue(of node: Node) -> VariableAssignment.Value? {
        var foundEq = false
        for child in node.children() {
            if !child.isNamed && child.text(in: context) == "=" {
                foundEq = true
                continue
            }
            if foundEq {
                return assignmentSyntax.classifyValue(child)
            }
        }
        return nil
    }

    /// Infers a property's type from a direct construction initializer (`Helper()`, no navigation so
    /// `foo.Bar()` isn't mistaken for one), when the callee is a same-file declared type.
    private func constructedTypeRef(from initializerNode: Node?) -> TypeReference? {
        guard let call = initializerNode, call.nodeType == "call_expression",
              call.firstChild(withType: "navigation_expression") == nil,
              let callee = call.firstChild(withType: "simple_identifier"),
              declarations.declaredTypeNames.contains(callee.text(in: context))
        else { return nil }
        return TypeReference(name: callee.text(in: context))
    }

    private func extractFirstTypeRef(from node: Node) -> TypeReference? {
        for child in node.namedChildren() {
            switch child.nodeType {
            case "user_type":
                return extractTypeReference(child)
            case "nullable_type":
                return extractNullableType(child)
            case "function_type":
                return extractFunctionType(child)
            default:
                break
            }
        }
        return nil
    }

    // MARK: - Secondary Constructor

    func extractSecondaryConstructor(
        _ node: Node,
        scope: CallSiteScope = CallSiteScope()
    ) -> Member {
        let modifierInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        let params = extractFunctionValueParameters(
            node.firstChild(withType: "function_value_parameters")
        )
        // The constructor body has no `block` wrapper; statements sit inline under this node.
        let body = node.firstChild(withType: "block")
            ?? node.firstChild(withType: "statements")
        return Member(
            name: "init", kind: .initializer,
            accessLevel: modifierInfo.accessLevel,
            parameters: params, location: node.location(in: context),
            callSites: callSites.callSites(in: body, scope: scope.merging(parameters: params)),
            assignments: assignments.assignments(in: body),
            fieldReads: fieldReads.reads(in: body, scope: scope)
        )
    }

    // MARK: - Primary Constructor Parameters

    struct ClassParam {
        let parameter: Parameter
        let isProperty: Bool
        let isReadOnly: Bool
        let accessLevel: AccessLevel
        let modifiers: [Modifier]
        let annotations: [String]
    }

    func extractPrimaryConstructorParams(_ node: Node?) -> [ClassParam] {
        guard let node else { return [] }
        let classParamsNode = node.firstChild(withType: "class_parameters") ?? node
        return classParamsNode.allChildren(withType: "class_parameter").map { child in
            let paramModInfo = extractModifiers(child.firstChild(withType: "modifiers"))
            let binding = bindingKind(of: child)
            let isVal = binding == "val"
            let isVar = binding == "var"
            let isProperty = isVal || isVar
            let name = child.firstChild(withType: "simple_identifier").map { $0.text(in: context) } ?? ""
            let typeRef = extractFirstTypeRef(from: child)
            var defaultValue: String?
            var foundEq = false
            for innerChild in child.children() {
                if !innerChild.isNamed && innerChild.text(in: context) == "=" {
                    foundEq = true
                    continue
                }
                if foundEq && innerChild.isNamed {
                    defaultValue = innerChild.text(in: context)
                    break
                }
            }
            return ClassParam(
                parameter: Parameter(
                    internalName: name, type: typeRef,
                    defaultValue: defaultValue
                ),
                isProperty: isProperty,
                isReadOnly: isVal,
                accessLevel: paramModInfo.accessLevel,
                modifiers: paramModInfo.modifiers,
                annotations: paramModInfo.annotations
            )
        }
    }

    // MARK: - Function Value Parameters

    func extractFunctionValueParameters(_ node: Node?) -> [Parameter] {
        guard let node else { return [] }
        return node.allChildren(withType: "parameter").map { child in
            let name = child.firstChild(withType: "simple_identifier").map { $0.text(in: context) } ?? ""
            let typeRef = extractFirstTypeRef(from: child)
            var defaultValue: String?
            var foundEq = false
            for innerChild in child.children() {
                if !innerChild.isNamed && innerChild.text(in: context) == "=" {
                    foundEq = true
                    continue
                }
                if foundEq && innerChild.isNamed {
                    defaultValue = innerChild.text(in: context)
                    break
                }
            }
            return Parameter(
                internalName: name, type: typeRef,
                defaultValue: defaultValue,
                isVariadic: hasKeyword("vararg", in: child)
            )
        }
    }
}
