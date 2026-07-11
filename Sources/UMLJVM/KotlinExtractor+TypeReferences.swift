import UMLCore
import UMLTreeSitter

// MARK: - Type References & Relationships

extension KotlinExtractor {

    // MARK: - Supertype Classification

    /// A type reference paired with whether it came from a constructor invocation
    /// (class inheritance) or a bare type / delegation (interface conformance).
    struct ClassifiedSupertype {
        let typeRef: TypeReference
        let isClassInheritance: Bool
    }

    func classifySupertypes(_ specifiers: [Node]) -> [ClassifiedSupertype] {
        specifiers.compactMap { specifier in
            if let constructorInvocation = specifier.firstChild(withType: "constructor_invocation"),
               let userTypeNode = constructorInvocation.firstChild(withType: "user_type") {
                return ClassifiedSupertype(typeRef: extractTypeReference(userTypeNode), isClassInheritance: true)
            } else if let userTypeNode = specifier.firstChild(withType: "user_type") {
                return ClassifiedSupertype(typeRef: extractTypeReference(userTypeNode), isClassInheritance: false)
            } else if let explicitDelegation = specifier.firstChild(withType: "explicit_delegation"),
                      let userTypeNode = explicitDelegation.firstChild(withType: "user_type") {
                return ClassifiedSupertype(typeRef: extractTypeReference(userTypeNode), isClassInheritance: false)
            }
            return nil
        }
    }

    // MARK: - Type References

    func extractTypeReferenceFromAny(_ node: Node) -> TypeReference {
        switch node.nodeType {
        case "user_type":
            return extractTypeReference(node)
        case "nullable_type":
            return extractNullableType(node)
        case "function_type":
            return extractFunctionType(node)
        case "parenthesized_type":
            return node.namedChildren().first.map { extractTypeReferenceFromAny($0) }
                ?? TypeReference(name: text(node))
        default:
            return TypeReference(name: text(node))
        }
    }

    func extractTypeReference(_ node: Node) -> TypeReference {
        var nameParts: [String] = []
        var genericArgs: [TypeReference] = []
        for child in node.namedChildren() {
            switch child.nodeType {
            case "type_identifier":
                nameParts.append(text(child))
            case "user_type":
                // Nested user_type nodes appear for qualified references
                // like `com.example.Animal` or `Outer.Inner`.
                let nested = extractTypeReference(child)
                if !nested.name.isEmpty {
                    nameParts.append(nested.name)
                }
            case "type_arguments":
                genericArgs = extractTypeArguments(child)
            default:
                break
            }
        }
        return TypeReference(name: nameParts.joined(separator: "."), genericArguments: genericArgs)
    }

    func extractNullableType(_ node: Node) -> TypeReference {
        if let inner = node.namedChildren().first {
            var ref = extractTypeReferenceFromAny(inner)
            ref.isOptional = true
            return ref
        }
        var typeName = text(node)
        if typeName.hasSuffix("?") { typeName = String(typeName.dropLast()) }
        return TypeReference(name: typeName, isOptional: true)
    }

    func extractFunctionType(_ node: Node) -> TypeReference { TypeReference(name: text(node)) }

    func extractTypeArguments(_ node: Node) -> [TypeReference] {
        node.namedChildren().compactMap { child in
            switch child.nodeType {
            case "type_projection":
                if let star = child.firstChild(withType: "star_projection") { return TypeReference(name: text(star)) }
                return child.namedChildren().first.map { extractTypeReferenceFromAny($0) }
            case "user_type":
                return extractTypeReference(child)
            case "nullable_type":
                return extractNullableType(child)
            default:
                return nil
            }
        }
    }

    // MARK: - Call Site Resolution

    /// Resolves statically-determinable Kotlin call patterns:
    /// - `receiver.method(args)` / `this.receiver.method(args)` where `receiver` is a known property,
    /// - `this.method(args)` — a call on the enclosing instance,
    /// - `TypeName.method(args)` where `TypeName` is a known (companion/static) type.
    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        guard node.nodeType == "call_expression" else { return nil }

        guard let navExpr = node.firstChild(withType: "navigation_expression") else {
            // Bare `foo()` — an implicit-receiver call (a member of the enclosing type or a top-level
            // function). Tagged `.selfDispatch`; the builder falls back to a free function. The
            // `knownTypeNames` guard drops constructor calls `Foo()`, which share this grammar shape.
            guard let calleeId = node.firstChild(withType: "simple_identifier") else { return nil }
            return scope.bareCall(named: text(calleeId), implicitSelf: true, location: loc(node))
        }

        // Method name lives in the last navigation_suffix → simple_identifier
        guard let navSuffix = navExpr.firstChild(withType: "navigation_suffix"),
              let methodNode = navSuffix.firstChild(withType: "simple_identifier")
        else { return nil }
        let methodName = text(methodNode)

        // Pattern: this.method(args) — a direct call on the enclosing instance.
        if navExpr.firstChild(withType: "this_expression") != nil {
            return CallSite(receiver: .selfDispatch, methodName: methodName, location: loc(node))
        }

        // Resolve receiver variable / type name.
        var receiverName: String?
        if let firstId = navExpr.firstChild(withType: "simple_identifier") {
            // Pattern: receiver.method(args)
            receiverName = text(firstId)
        } else if let innerNav = navExpr.firstChild(withType: "navigation_expression"),
                  innerNav.firstChild(withType: "this_expression") != nil,
                  let innerSuffix = innerNav.firstChild(withType: "navigation_suffix"),
                  let propId = innerSuffix.firstChild(withType: "simple_identifier") {
            // Pattern: this.receiver.method(args)
            receiverName = text(propId)
        }

        guard let name = receiverName else { return nil }
        return scope.resolvedCallSite(receiverName: name, methodName: methodName, location: loc(node))
    }

    /// Provable local-variable types: an explicit annotation (`val x: Foo`) or a `Foo()` construction
    /// of a declared type (`val x = Foo()`), so `x.method()` resolves to `Foo` (RC4).
    func localBindings(in body: Node) -> [String: String] {
        collectLocalBindings(in: body) { node in
            guard node.nodeType == "property_declaration",
                  let varDecl = node.firstChild(withType: "variable_declaration"),
                  let nameNode = varDecl.firstChild(withType: "simple_identifier")
            else { return nil }
            let name = text(nameNode)
            if let userType = varDecl.firstChild(withType: "user_type"),
               let typeId = userType.firstChild(withType: "type_identifier") {
                return (name, text(typeId))
            }
            if let call = node.firstChild(withType: "call_expression"),
               call.firstChild(withType: "navigation_expression") == nil,
               let callee = call.firstChild(withType: "simple_identifier"),
               declaredTypeNames.contains(text(callee)) {
                return (name, text(callee))
            }
            return nil
        }
    }

    // MARK: - Generic Parameters

    func extractTypeParameters(_ node: Node?) -> [GenericParameter] {
        guard let node else { return [] }
        return node.allChildren(withType: "type_parameter").compactMap { child in
            let name = child.firstChild(withType: "type_identifier").map { text($0) }
                ?? child.firstChild(withType: "simple_identifier").map { text($0) }
                ?? ""
            guard !name.isEmpty else { return nil }
            var constraints: [GenericConstraint] = []
            if let userTypeNode = child.firstChild(withType: "user_type") {
                constraints.append(GenericConstraint(kind: .conformance, type: extractTypeReference(userTypeNode)))
            } else if let nullableTypeNode = child.firstChild(withType: "nullable_type") {
                constraints.append(GenericConstraint(kind: .conformance, type: extractNullableType(nullableTypeNode)))
            }
            return GenericParameter(name: name, constraints: constraints)
        }
    }
}
