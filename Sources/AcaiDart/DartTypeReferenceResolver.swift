import Foundation
import AcaiCore
import AcaiTreeSitter

// MARK: - DartTypeReferenceResolver

/// Reads Dart type syntax — type references, generic parameters, supertype lists, class modifiers
/// and the type/modifier prefix of a variable declaration. Stateless beyond `context`.
struct DartTypeReferenceResolver {
    let context: SourceFileContext

    // MARK: - Type References

    func typeReference(_ node: Node) -> TypeReference? {
        guard let nodeType = node.nodeType else { return nil }
        switch nodeType {
        case "type_identifier", "identifier":
            let name = node.text(in: context)
            let isOptional = node.parent?.nodeType == "nullable_type"
            return TypeReference(name: name, isOptional: isOptional)
        case "nullable_type":
            for child in node.namedChildren() {
                if let ref = typeReference(child) {
                    return TypeReference(
                        name: ref.name, genericArguments: ref.genericArguments,
                        isOptional: true, isArray: ref.isArray
                    )
                }
            }
            return nil
        case "generic_type", "type_arguments":
            return genericType(node)
        case "void_type":
            return TypeReference(name: "void")
        case "function_type":
            return TypeReference(name: node.text(in: context))
        case "inferred_type":
            return TypeReference(name: "var")
        default:
            let typeText = node.text(in: context).trimmingCharacters(in: .whitespacesAndNewlines)
            return typeText.isEmpty ? nil : TypeReference(name: typeText)
        }
    }

    private func genericType(_ node: Node) -> TypeReference? {
        var name = ""
        var genericArgs: [TypeReference] = []

        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            switch childType {
            case "type_identifier", "identifier":
                if name.isEmpty { name = child.text(in: context) }
            case "type_arguments":
                genericArgs = child.namedChildren().compactMap { typeReference($0) }
            default:
                break
            }
        }

        guard !name.isEmpty else { return nil }
        let isArray = name == "List"
        return TypeReference(name: name, genericArguments: genericArgs, isArray: isArray)
    }

    // MARK: - Type Parameters (Generics)

    func typeParameters(from node: Node) -> [GenericParameter] {
        if let typeParamsNode = node.child(byFieldName: "type_parameters") {
            return typeParameterList(typeParamsNode)
        }
        return typeParametersFromChildren(node)
    }

    func typeParametersFromChildren(_ node: Node) -> [GenericParameter] {
        for child in node.children() where child.nodeType == "type_parameters" {
            return typeParameterList(child)
        }
        return []
    }

    func typeParameterList(_ node: Node) -> [GenericParameter] {
        node.allChildren(withType: "type_parameter").map { typeParameter($0) }
    }

    private func typeParameter(_ node: Node) -> GenericParameter {
        var name = ""
        var constraints: [GenericConstraint] = []

        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            switch childType {
            case "type_identifier", "identifier":
                if name.isEmpty { name = child.text(in: context) } else {
                    constraints.append(GenericConstraint(
                        kind: .superclass,
                        type: TypeReference(name: child.text(in: context))
                    ))
                }
            default:
                break
            }
        }
        return GenericParameter(name: name, constraints: constraints)
    }

    // MARK: - Superclass / Type Lists

    func superclassTypes(_ node: Node) -> [TypeReference] {
        // When the grammar emits `type_identifier` and `type_arguments` as siblings (instead of
        // wrapping them in `generic_type`), combine them into one TypeReference to avoid spurious
        // edges to generic-argument types.
        var refs: [TypeReference] = []
        var pendingName: String?

        for child in node.namedChildren() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "mixins" { continue }

            if nodeType == "type_identifier" || nodeType == "identifier" {
                if let name = pendingName {
                    refs.append(TypeReference(name: name))
                }
                pendingName = child.text(in: context)
            } else if nodeType == "type_arguments", let name = pendingName {
                let genericArgs = child.namedChildren().compactMap { typeReference($0) }
                refs.append(TypeReference(name: name, genericArguments: genericArgs))
                pendingName = nil
            } else {
                if let name = pendingName {
                    refs.append(TypeReference(name: name))
                    pendingName = nil
                }
                if let ref = typeReference(child) {
                    refs.append(ref)
                }
            }
        }

        if let name = pendingName {
            refs.append(TypeReference(name: name))
        }
        return refs
    }

    func typeList(_ node: Node) -> [TypeReference] {
        var refs: [TypeReference] = []
        for child in node.namedChildren() {
            if child.nodeType == "type_not_void_list" || child.nodeType == "_type_not_void_list" {
                refs.append(contentsOf: typeListFromChildren(child))
            } else if let ref = typeReference(child) {
                refs.append(ref)
            }
        }
        return refs
    }

    func typeListFromChildren(_ node: Node) -> [TypeReference] {
        node.namedChildren().compactMap { typeReference($0) }
    }

    // MARK: - Class Modifiers

    func classModifiers(_ node: Node) -> [Modifier] {
        var modifiers: [Modifier] = []
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            let modifierText = child.text(in: context)
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
        return modifiers.uniqued()
    }

    // MARK: - Declaration Info

    /// The type and modifier prefix of a variable declaration (`static late final Foo? x`), read
    /// one child at a time because the grammar flattens it into siblings of the identifier list.
    struct DeclarationInfo {
        var type: TypeReference?
        var isNullable = false
        var isStatic = false
        var isLate = false
        var isFinal = false
        var isConst = false

        /// Applies the `isNullable` flag collected from a `nullable_type` child onto `type`, which
        /// only becomes known once every child has been seen.
        func resolvingNullableType() -> DeclarationInfo {
            var info = self
            if info.isNullable, let base = info.type {
                info.type = TypeReference(
                    name: base.name, genericArguments: base.genericArguments,
                    isOptional: true, isArray: base.isArray
                )
            }
            return info
        }
    }

    /// Folds one modifier/type child of a `declaration` node (or, at file scope, of `program`
    /// itself — the two share this per-child shape even though only the class-body form is
    /// actually wrapped in a `declaration` node) into `info`.
    func apply(_ child: Node, nodeType: String, to info: inout DeclarationInfo) {
        switch nodeType {
        case "type_identifier", "generic_type", "function_type", "void_type":
            if info.type == nil { info.type = typeReference(child) }
        case "type_arguments":
            if let base = info.type {
                let args = child.namedChildren().compactMap { typeReference($0) }
                info.type = TypeReference(
                    name: base.name, genericArguments: args,
                    isArray: base.name == "List"
                )
            }
        case "nullable_type":
            info.isNullable = true
        case "final_builtin":
            info.isFinal = true
        case "const_builtin":
            info.isConst = true
        default:
            break
        }
    }

    /// First pass over a `declaration` node to collect type and modifier info.
    func declarationInfo(_ node: Node) -> DeclarationInfo {
        var info = DeclarationInfo(
            isStatic: node.hasAnonymousChild("static", in: context),
            isLate: node.hasAnonymousChild("late", in: context)
        )
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            apply(child, nodeType: nodeType, to: &info)
        }
        return info.resolvingNullableType()
    }
}
