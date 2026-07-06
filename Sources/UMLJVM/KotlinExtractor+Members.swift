import UMLCore
import UMLTreeSitter

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
        // Use the parent type's qualified ID as namespace so that nested
        // types receive correctly-qualified IDs (e.g. `pkg.Outer.Inner`).
        let savedNamespace = currentNamespace
        currentNamespace = typeDecl.id
        defer { currentNamespace = savedNamespace }

        // Pre-scan: build property → type map for call-site resolution.
        var knownProperties: [String: String] = [:]
        for member in typeDecl.members where member.kind == .property {
            if let typeName = member.type?.name {
                knownProperties[member.name] = typeName
            }
        }
        for child in node.namedChildren()
            where child.nodeType == "property_declaration" {
            let prop = extractPropertyDeclaration(child)
            if !prop.modifiers.contains(.static),
               let typeName = prop.type?.name {
                knownProperties[prop.name] = typeName
            }
        }

        let scope = CallSiteScope(
            knownProperties: knownProperties,
            knownTypeNames: declaredTypeNames
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
                    child, isComputed: hasGetterOrSetter
                )
            )
        case "secondary_constructor":
            context.typeDecl.members.append(
                extractSecondaryConstructor(
                    child,
                    scope: context.scope
                )
            )
        case "companion_object":
            if let obj = extractCompanionObject(child) {
                context.typeDecl.nestedTypes.append(obj)
            }
        case "class_declaration":
            handleNestedClassDeclaration(
                child, into: &context.typeDecl
            )
        case "object_declaration":
            if let nestedType = extractObjectDeclaration(child) {
                context.typeDecl.nestedTypes.append(nestedType)
            }
        default:
            break
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
        let name = text(nameNode)
        var rawValue: String?
        if let valueArgs = node.firstChild(withType: "value_arguments") {
            let argsText = text(valueArgs).trimmingCharacters(in: .whitespaces)
            rawValue = (argsText.hasPrefix("(") && argsText.hasSuffix(")"))
                ? String(argsText.dropFirst().dropLast()) : argsText
        }
        return EnumCase(name: name, rawValue: rawValue, location: loc(node))
    }

    // MARK: - Function Declaration

    mutating func extractFunctionDeclaration(
        _ node: Node,
        scope: CallSiteScope = CallSiteScope()
    ) -> Member {
        let modifierInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        let name = node.firstChild(withType: "simple_identifier").map { text($0) } ?? "_anonymous"
        let generics = extractTypeParameters(node.firstChild(withType: "type_parameters"))

        // Extension function receiver (e.g. `fun String.hello() {}`)
        if let receiverRef = extractReceiverType(node) {
            relationships.append(
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
        let callSites = extractCallSites(from: body, scope: scope)

        return Member(
            name: name, kind: .method,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            type: returnType, parameters: params,
            genericParameters: generics, annotations: modifierInfo.annotations,
            location: loc(node), callSites: callSites,
            assignments: extractAssignments(from: body),
            fieldReads: fieldReadResolver.reads(in: body, scope: scope),
            referencedTypeNames: referencedTypeNames(in: body),
            cyclomaticComplexity: cyclomaticComplexity(in: body, branchKinds: Self.branchNodeKinds)
        )
    }

    /// Extracts the receiver type from a Kotlin extension function declaration.
    ///
    /// In `fun String.hello() {}`, `String` is the receiver type. The tree-sitter
    /// AST places this as a type node child followed by a `"."` anonymous child
    /// before the function name.
    private func extractReceiverType(_ node: Node) -> TypeReference? {
        let children = node.children()
        guard let funIndex = children.firstIndex(where: {
            !$0.isNamed && text($0) == "fun"
        }) else { return nil }
        var childIndex = children.index(after: funIndex)
        while childIndex < children.endIndex {
            let child = children[childIndex]
            // Skip type parameters (generics before receiver)
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
                   text(children[nextIndex]) == "." {
                    return extractTypeReferenceFromAny(child)
                }
            }
            break // Not an extension function
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
            if foundParams && !child.isNamed && text(child) == ":" {
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
        isComputed: Bool = false
    ) -> Member {
        let modifierInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        let isVal = bindingKind(of: node) == "val"
        var modifiers = modifierInfo.modifiers
        if isVal { modifiers.append(.readonly) }

        var name = ""
        var typeRef: TypeReference?

        if let varDecl = node.firstChild(withType: "variable_declaration") {
            name = varDecl.firstChild(withType: "simple_identifier").map { text($0) } ?? ""
            typeRef = extractFirstTypeRef(from: varDecl)
        } else {
            name = node.firstChild(withType: "simple_identifier").map { text($0) } ?? ""
            typeRef = extractFirstTypeRef(from: node)
        }

        return Member(
            name: name, kind: .property,
            accessLevel: modifierInfo.accessLevel, modifiers: modifiers,
            type: typeRef,
            isComputed: isComputed,
            annotations: modifierInfo.annotations, location: loc(node),
            initialValue: propertyInitializerValue(of: node),
            referencedTypeNames: referencedTypeNames(in: propertyInitializerNode(of: node))
        )
    }

    /// The property's initializer expression node (the node after the anonymous `=`), if present.
    /// Used for construction/body dependencies; accessor (`get()/set()`) bodies are deliberately not
    /// walked.
    private func propertyInitializerNode(of node: Node) -> Node? {
        var foundEq = false
        for child in node.children() {
            if !child.isNamed && text(child) == "=" {
                foundEq = true
                continue
            }
            if foundEq { return child }
        }
        return nil
    }

    /// Classifies the property's initializer expression (the node after the
    /// anonymous `=` token), when present. The expression may itself be an
    /// anonymous token (`null`), so namedness is not required.
    private func propertyInitializerValue(of node: Node) -> VariableAssignment.Value? {
        var foundEq = false
        for child in node.children() {
            if !child.isNamed && text(child) == "=" {
                foundEq = true
                continue
            }
            if foundEq {
                return classifyValue(child)
            }
        }
        return nil
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
        // The constructor body has no `block` wrapper; statements sit inline
        // under the `secondary_constructor` node (between anonymous braces).
        let body = node.firstChild(withType: "block")
            ?? node.firstChild(withType: "statements")
        return Member(
            name: "init", kind: .initializer,
            accessLevel: modifierInfo.accessLevel,
            parameters: params, location: loc(node),
            callSites: extractCallSites(from: body, scope: scope),
            assignments: extractAssignments(from: body),
            fieldReads: fieldReadResolver.reads(in: body, scope: scope)
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
            let name = child.firstChild(withType: "simple_identifier").map { text($0) } ?? ""
            let typeRef = extractFirstTypeRef(from: child)
            var defaultValue: String?
            var foundEq = false
            for innerChild in child.children() {
                if !innerChild.isNamed && text(innerChild) == "=" {
                    foundEq = true
                    continue
                }
                if foundEq && innerChild.isNamed {
                    defaultValue = text(innerChild)
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
            let name = child.firstChild(withType: "simple_identifier").map { text($0) } ?? ""
            let typeRef = extractFirstTypeRef(from: child)
            var defaultValue: String?
            var foundEq = false
            for innerChild in child.children() {
                if !innerChild.isNamed && text(innerChild) == "=" {
                    foundEq = true
                    continue
                }
                if foundEq && innerChild.isNamed {
                    defaultValue = text(innerChild)
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
