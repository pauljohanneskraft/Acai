import AcaiCore
import AcaiTreeSitter

// MARK: - JSTypeReferenceResolver

/// Resolves a JS/TS type-annotation or type-expression node into a `TypeReference`, and reads the
/// TypeScript-only accessibility modifier and generic-parameter lists. Stateless beyond `context`
/// and `isTypeScript`, which gate every TypeScript-only construct (JS has no type annotations).
struct JSTypeReferenceResolver {
    let context: SourceFileContext
    let isTypeScript: Bool

    private static let passthroughNodeTypes: Set<String> = [
        "predefined_type", "type_identifier", "identifier",
        "union_type", "intersection_type", "function_type", "literal_type",
        "tuple_type", "conditional_type", "index_type_query", "mapped_type",
        "type_query", "object_type", "template_literal_type", "existential_type",
        "nested_type_identifier", "member_expression", "this_type"
    ]

    private static let accessLevelMap: [String: AccessLevel] = [
        "public": .public, "private": .private, "protected": .protected
    ]

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

    private func extractTypeReference(_ node: Node) -> TypeReference {
        guard let nodeType = node.nodeType else {
            return TypeReference(name: node.text(in: context))
        }

        if Self.passthroughNodeTypes.contains(nodeType) {
            return TypeReference(name: node.text(in: context))
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
            return TypeReference(name: node.text(in: context))
        }
    }

    private func extractGenericTypeReference(_ node: Node) -> TypeReference {
        let nameNode = node.child(byFieldName: "name") ?? node.namedChildren().first
        let name = nameNode.map { $0.text(in: context) } ?? node.text(in: context)
        var genericArgs: [TypeReference] = []
        if let typeArgs = node.child(byFieldName: "type_arguments")
            ?? node.firstChild(withType: "type_arguments") {
            genericArgs = typeArgs.namedChildren().map { extractTypeReference($0) }
        }
        return TypeReference(name: name, genericArguments: genericArgs)
    }

    private func extractArrayTypeReference(_ node: Node) -> TypeReference {
        guard let elementType = node.namedChildren().first else {
            return TypeReference(name: node.text(in: context), isArray: true)
        }
        let inner = extractTypeReference(elementType)
        return TypeReference(name: inner.name, genericArguments: inner.genericArguments, isArray: true)
    }

    private func extractWrappedTypeReference(_ node: Node) -> TypeReference {
        if let inner = node.namedChildren().first { return extractTypeReference(inner) }
        return TypeReference(name: node.text(in: context))
    }

    private func extractOptionalTypeReference(_ node: Node) -> TypeReference {
        guard let inner = node.namedChildren().first else {
            return TypeReference(name: node.text(in: context), isOptional: true)
        }
        var ref = extractTypeReference(inner)
        ref.isOptional = true
        return ref
    }

    func extractTypeReferenceFromExpression(_ node: Node) -> TypeReference {
        switch node.nodeType ?? "" {
        case "identifier", "type_identifier", "property_identifier":
            return TypeReference(name: node.text(in: context))
        case "generic_type":
            return extractTypeReference(node)
        default:
            return TypeReference(name: node.text(in: context))
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
            let name = nameNode.map { $0.text(in: context) } ?? ""
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

    func extractAccessibilityModifier(_ node: Node) -> AccessLevel? {
        for child in node.children() where child.nodeType == "accessibility_modifier" {
            if let level = Self.accessLevelMap[child.text(in: context)] { return level }
        }
        for child in node.children() where child.nodeType != "type_identifier" {
            if let level = Self.accessLevelMap[child.text(in: context)] { return level }
        }
        return nil
    }
}
