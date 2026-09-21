import AcaiCore
import AcaiTreeSitter

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
                ?? TypeReference(name: node.text(in: context))
        default:
            return TypeReference(name: node.text(in: context))
        }
    }

    func extractTypeReference(_ node: Node) -> TypeReference {
        var nameParts: [String] = []
        var genericArgs: [TypeReference] = []
        for child in node.namedChildren() {
            switch child.nodeType {
            case "type_identifier":
                nameParts.append(child.text(in: context))
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
        var typeName = node.text(in: context)
        if typeName.hasSuffix("?") { typeName = String(typeName.dropLast()) }
        return TypeReference(name: typeName, isOptional: true)
    }

    func extractFunctionType(_ node: Node) -> TypeReference { TypeReference(name: node.text(in: context)) }

    func extractTypeArguments(_ node: Node) -> [TypeReference] {
        node.namedChildren().compactMap { child in
            switch child.nodeType {
            case "type_projection":
                if let star = child.firstChild(withType: "star_projection") {
                    return TypeReference(name: star.text(in: context))
                }
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

    // MARK: - Generic Parameters

    func extractTypeParameters(_ node: Node?) -> [GenericParameter] {
        guard let node else { return [] }
        return node.allChildren(withType: "type_parameter").compactMap { child in
            let name = child.firstChild(withType: "type_identifier").map { $0.text(in: context) }
                ?? child.firstChild(withType: "simple_identifier").map { $0.text(in: context) }
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
