import UMLCore
import UMLTreeSitter

// MARK: - Type References, Generics & Call Sites

extension JavaExtractor {

    /// Matches Java `method_invocation` nodes.
    ///
    /// Handles:
    /// - `receiver.method(args)` — `object` field is an `identifier` (a known property or type),
    /// - `this.receiver.method(args)` — `object` is a `field_access` whose own `object` is `this`,
    /// - `this.method(args)` — `object` field is `this` (a call on the enclosing instance),
    /// - `TypeName.method(args)` — `object` is a known type (static call).
    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        guard node.nodeType == "method_invocation",
              let nameNode = node.child(byFieldName: "name"),
              let objectNode = node.child(byFieldName: "object")
        else { return nil }

        return resolveMemberCall(
            receiver: objectNode,
            methodName: text(nameNode),
            grammar: MemberCallGrammar(
                selfNodeType: "this", memberAccessType: "field_access", memberField: "field"
            ),
            scope: scope,
            location: loc(node)
        )
    }

    // MARK: - Type References

    func extractTypeReference(_ node: Node) -> TypeReference? {
        guard let nodeType = node.nodeType else { return nil }

        switch nodeType {
        case "type_identifier", "integral_type", "floating_point_type",
             "scoped_type_identifier":
            return TypeReference(name: text(node))
        case "void_type":
            return TypeReference(name: "void")
        case "boolean_type":
            return TypeReference(name: "boolean")
        case "generic_type":
            return extractGenericTypeReference(node)
        case "array_type":
            return extractArrayTypeReference(node)
        case "wildcard":
            return extractWildcard(node)
        case "annotated_type":
            return extractAnnotatedTypeReference(node)
        case "dimensions":
            return nil
        default:
            let typeName = text(node)
            return typeName.isEmpty ? nil : TypeReference(name: typeName)
        }
    }

    private func extractGenericTypeReference(_ node: Node) -> TypeReference {
        var name = ""
        var genericArgs: [TypeReference] = []
        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            switch childType {
            case "type_identifier", "scoped_type_identifier":
                name = text(child)
            case "type_arguments":
                genericArgs = extractTypeArguments(child)
            default:
                break
            }
        }
        return TypeReference(name: name, genericArguments: genericArgs)
    }

    private func extractArrayTypeReference(_ node: Node) -> TypeReference {
        if let elementNode = node.child(byFieldName: "element"),
           let elementRef = extractTypeReference(elementNode) {
            return TypeReference(
                name: elementRef.name, genericArguments: elementRef.genericArguments,
                isOptional: elementRef.isOptional, isArray: true
            )
        }
        let trimmed = text(node).replacingOccurrences(of: "[]", with: "")
        return TypeReference(name: trimmed, isArray: true)
    }

    private func extractAnnotatedTypeReference(_ node: Node) -> TypeReference? {
        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            if childType != "marker_annotation" && childType != "annotation" {
                if let ref = extractTypeReference(child) { return ref }
            }
        }
        return nil
    }

    private func extractWildcard(_ node: Node) -> TypeReference {
        var wildcardName = "?"
        var constraints: [TypeReference] = []

        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            if childType == "extends" || childType == "super" { continue }
            if let ref = extractTypeReference(child), ref.name != "?" {
                constraints.append(ref)
            }
        }

        let fullText = text(node)
        if fullText.contains("extends") || fullText.contains("super") {
            wildcardName = fullText
        }
        return TypeReference(name: wildcardName, genericArguments: constraints)
    }

    private func extractTypeArguments(_ node: Node) -> [TypeReference] {
        return node.namedChildren().compactMap { extractTypeReference($0) }
    }

    // MARK: - Type Parameters (Generics)

    func extractTypeParameters(from node: Node) -> [GenericParameter] {
        if let typeParamsNode = node.child(byFieldName: "type_parameters") {
            return extractTypeParameterList(typeParamsNode)
        }
        if let typeParamsNode = node.firstChild(withType: "type_parameters") {
            return extractTypeParameterList(typeParamsNode)
        }
        return []
    }

    private func extractTypeParameterList(_ node: Node) -> [GenericParameter] {
        return node.allChildren(withType: "type_parameter").map { extractTypeParameter($0) }
    }

    private func extractTypeParameter(_ node: Node) -> GenericParameter {
        var name = ""
        var constraints: [GenericConstraint] = []

        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            switch childType {
            case "type_identifier", "identifier":
                if name.isEmpty { name = text(child) }
            case "type_bound":
                constraints = extractTypeBound(child)
            default:
                break
            }
        }
        return GenericParameter(name: name, constraints: constraints)
    }

    private func extractTypeBound(_ node: Node) -> [GenericConstraint] {
        var constraints: [GenericConstraint] = []
        var isFirst = true
        for child in node.namedChildren() {
            if let ref = extractTypeReference(child) {
                let kind: GenericConstraint.Kind = isFirst ? .superclass : .conformance
                constraints.append(GenericConstraint(kind: kind, type: ref))
                isFirst = false
            }
        }
        return constraints
    }

    // MARK: - Superclass / Interface Lists

    func extractSuperclassTypes(_ node: Node) -> [TypeReference] {
        return node.namedChildren().compactMap { extractTypeReference($0) }
    }

    func extractTypeList(_ node: Node) -> [TypeReference] {
        var refs: [TypeReference] = []
        for child in node.namedChildren() {
            if child.nodeType == "type_list" {
                refs.append(contentsOf: extractTypeList(child))
            } else if let ref = extractTypeReference(child) {
                refs.append(ref)
            }
        }
        return refs
    }
}
