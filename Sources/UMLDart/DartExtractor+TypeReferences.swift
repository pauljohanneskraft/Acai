import Foundation
import UMLCore
import UMLTreeSitter

// MARK: - Parameters, Types & Utilities

extension DartExtractor {

    func extractFormalParameterList(_ node: Node) -> [Parameter] {
        var params: [Parameter] = []
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "formal_parameter", "normal_formal_parameter":
                if let parameter = extractFormalParameter(child) { params.append(parameter) }
            case "default_formal_parameter":
                if let parameter = extractDefaultFormalParameter(child) { params.append(parameter) }
            case "optional_positional_formal_parameters", "optional_named_formal_parameters":
                for innerChild in child.children() {
                    if let childType = innerChild.nodeType,
                       childType == "default_formal_parameter"
                        || childType == "formal_parameter"
                        || childType == "normal_formal_parameter" {
                        if let parameter = extractDefaultFormalParameter(innerChild)
                            ?? extractFormalParameter(innerChild) {
                            params.append(parameter)
                        }
                    }
                }
            default:
                break
            }
        }
        return params
    }

    private func extractFormalParameter(_ node: Node) -> Parameter? {
        var paramType: TypeReference?
        var name = ""
        var modifiers: [Modifier] = []

        // Check for field formal parameter (this.name).
        let fullText = text(node)
        if fullText.contains("this.") {
            let parts = fullText.components(separatedBy: "this.")
            if parts.count >= 2 {
                let afterThis = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let paramName = afterThis
                    .components(separatedBy: CharacterSet.alphanumerics.inverted).first ?? afterThis
                return Parameter(internalName: paramName, type: nil)
            }
        }

        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            switch childType {
            case "identifier":
                let childText = text(child)
                if paramType == nil && name.isEmpty {
                    // Could be either the type or the name. If there's only one identifier, it's the name.
                    name = childText
                } else if !name.isEmpty && paramType == nil {
                    // Previous identifier was the type; this one is the name.
                    paramType = TypeReference(name: name)
                    name = childText
                }
            case "type_identifier", "generic_type", "function_type", "void_type":
                paramType = extractTypeReference(child)
            case "final_builtin":
                modifiers.append(.final)
            case "covariant":
                modifiers.append(.covariant)
            case "required":
                modifiers.append(.required)
            default:
                if paramType == nil, let ref = extractTypeReference(child) {
                    paramType = ref
                }
            }
        }

        guard !name.isEmpty else { return nil }
        return Parameter(internalName: name, type: paramType, modifiers: modifiers)
    }

    private func extractDefaultFormalParameter(_ node: Node) -> Parameter? {
        // default_formal_parameter wraps a normal_formal_parameter or formal_parameter with a default value.
        for child in node.children() {
            if child.nodeType == "formal_parameter" || child.nodeType == "normal_formal_parameter" {
                return extractFormalParameter(child)
            }
        }
        return extractFormalParameter(node)
    }

    // MARK: - Type References

    func extractTypeReference(_ node: Node) -> TypeReference? {
        guard let nodeType = node.nodeType else { return nil }
        switch nodeType {
        case "type_identifier", "identifier":
            let name = text(node)
            let isOptional = node.parent?.nodeType == "nullable_type"
            return TypeReference(name: name, isOptional: isOptional)
        case "nullable_type":
            for child in node.namedChildren() {
                if let ref = extractTypeReference(child) {
                    return TypeReference(
                        name: ref.name, genericArguments: ref.genericArguments,
                        isOptional: true, isArray: ref.isArray
                    )
                }
            }
            return nil
        case "generic_type", "type_arguments":
            return extractGenericType(node)
        case "void_type":
            return TypeReference(name: "void")
        case "function_type":
            return TypeReference(name: text(node))
        case "inferred_type":
            return TypeReference(name: "var")
        default:
            let typeText = text(node).trimmingCharacters(in: .whitespacesAndNewlines)
            return typeText.isEmpty ? nil : TypeReference(name: typeText)
        }
    }

    private func extractGenericType(_ node: Node) -> TypeReference? {
        var name = ""
        var genericArgs: [TypeReference] = []

        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            switch childType {
            case "type_identifier", "identifier":
                if name.isEmpty { name = text(child) }
            case "type_arguments":
                genericArgs = child.namedChildren().compactMap { extractTypeReference($0) }
            default:
                break
            }
        }

        guard !name.isEmpty else { return nil }
        let isArray = name == "List"
        return TypeReference(name: name, genericArguments: genericArgs, isArray: isArray)
    }

    // MARK: - Type Parameters (Generics)

    func extractTypeParameters(from node: Node) -> [GenericParameter] {
        if let typeParamsNode = node.child(byFieldName: "type_parameters") {
            return extractTypeParameterList(typeParamsNode)
        }
        return extractTypeParametersFromChildren(node)
    }

    func extractTypeParametersFromChildren(_ node: Node) -> [GenericParameter] {
        for child in node.children() where child.nodeType == "type_parameters" {
            return extractTypeParameterList(child)
        }
        return []
    }

    func extractTypeParameterList(_ node: Node) -> [GenericParameter] {
        return node.allChildren(withType: "type_parameter").map { extractTypeParameter($0) }
    }

    private func extractTypeParameter(_ node: Node) -> GenericParameter {
        var name = ""
        var constraints: [GenericConstraint] = []

        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            switch childType {
            case "type_identifier", "identifier":
                if name.isEmpty { name = text(child) } else {
                    constraints.append(GenericConstraint(
                        kind: .superclass,
                        type: TypeReference(name: text(child))
                    ))
                }
            default:
                break
            }
        }
        return GenericParameter(name: name, constraints: constraints)
    }

    // MARK: - Superclass / Type Lists

    func extractSuperclassTypes(_ node: Node) -> [TypeReference] {
        // superclass: 'extends' type optional(mixins) | mixins
        //
        // When the grammar emits `type_identifier` and `type_arguments` as
        // siblings (instead of wrapping them in a `generic_type` node), combine
        // them into a single TypeReference so we avoid spurious edges to
        // generic-argument types.
        var refs: [TypeReference] = []
        var pendingName: String?

        for child in node.namedChildren() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "mixins" { continue }

            if nodeType == "type_identifier" || nodeType == "identifier" {
                // Flush any previously pending simple name.
                if let name = pendingName {
                    refs.append(TypeReference(name: name))
                }
                pendingName = text(child)
            } else if nodeType == "type_arguments", let name = pendingName {
                let genericArgs = child.namedChildren().compactMap { extractTypeReference($0) }
                refs.append(TypeReference(name: name, genericArguments: genericArgs))
                pendingName = nil
            } else {
                // Flush pending name, then handle generic_type and other nodes.
                if let name = pendingName {
                    refs.append(TypeReference(name: name))
                    pendingName = nil
                }
                if let ref = extractTypeReference(child) {
                    refs.append(ref)
                }
            }
        }

        // Flush trailing simple name.
        if let name = pendingName {
            refs.append(TypeReference(name: name))
        }
        return refs
    }

    func extractTypeList(_ node: Node) -> [TypeReference] {
        var refs: [TypeReference] = []
        for child in node.namedChildren() {
            if child.nodeType == "type_not_void_list" || child.nodeType == "_type_not_void_list" {
                refs.append(contentsOf: extractTypeListFromChildren(child))
            } else if let ref = extractTypeReference(child) {
                refs.append(ref)
            }
        }
        return refs
    }

    func extractTypeListFromChildren(_ node: Node) -> [TypeReference] {
        return node.namedChildren().compactMap { extractTypeReference($0) }
    }

    // MARK: - Class Modifiers

    func extractClassModifiers(_ node: Node) -> [Modifier] {
        var modifiers: [Modifier] = []
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            let modifierText = text(child)
            switch modifierText {
            case "abstract":
                modifiers.append(.abstract)
            case "sealed":
                modifiers.append(.sealed)
            case "final":
                modifiers.append(.final)
            default:
                break
            }
            if nodeType == "abstract" { modifiers.append(.abstract) }
            if nodeType == "sealed" { modifiers.append(.sealed) }
        }
        // Deduplicate.
        return Array(Set(modifiers))
    }

    // MARK: - Access Level

    /// In Dart, identifiers starting with `_` are private to the library.
    func accessLevel(for name: String) -> AccessLevel {
        name.hasPrefix("_") ? .private : .public
    }
}
