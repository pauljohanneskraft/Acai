import AcaiCore
import AcaiTreeSitter

// MARK: - Body Extraction

extension KotlinExtractor {

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
            let prop = memberExtractor.propertyDeclaration(child)
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
                  let returnTypeNode = memberExtractor.returnTypeNode(in: child)
            else { continue }
            let returnType = typeReferences.extractTypeReferenceFromAny(returnTypeNode)
            guard returnType.name != "Unit" else { continue }
            returnTypes.record(returnType.name, for: nameNode.text(in: context))
        }

        let scope = CallSiteScope(
            knownProperties: knownProperties,
            knownTypeNames: declarations.declaredTypeNames,
            knownMethodReturnTypes: returnTypes.resolved
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
            context.typeDecl.members.append(extractFunctionDeclaration(child, scope: context.scope))
        case "property_declaration":
            let hasGetterOrSetter = nextSiblingIsAccessor(at: index, in: context.siblings)
            context.typeDecl.members.append(
                memberExtractor.propertyDeclaration(child, isComputed: hasGetterOrSetter, scope: context.scope)
            )
        case "anonymous_initializer":
            // An `init { … }` block — Kotlin's real constructor body. Record its calls on an
            // `.initializer` member so they're never a dead-code false positive.
            context.typeDecl.members.append(memberExtractor.anonymousInitializer(child, scope: context.scope))
        case "secondary_constructor":
            context.typeDecl.members.append(memberExtractor.secondaryConstructor(child, scope: context.scope))
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
}
