import Foundation
import UMLCore
import UMLTreeSitter

/// Resolves a Python type-expression node to a `TypeReference`, unwrapping the typing module's
/// wrappers (`Optional`, `Union`, PEP 604 `X | Y`, `Final`, `ClassVar`, `Annotated`) to the type
/// identity they carry. A real per-language behavior (the design doc's `TypeReferenceResolver`
/// seam) — Python's type-expression grammar shares nothing structural with another language's.
struct PythonTypeReference: Sendable {
    private static let transparentWrappers: Set<String> = ["Final", "ClassVar", "Annotated"]

    /// A `TypeReferenceResolver` closure backed by this value's `resolve(_:in:)`.
    var resolver: TypeReferenceResolver {
        TypeReferenceResolver { node, source in
            PythonTypeReference().resolve(node, in: source)
        }
    }

    func resolve(_ node: Node, in source: ParsedSource) -> TypeReference {
        let inner = (node.nodeType == "type") ? node.namedChildren().first : node
        return inner.map { reference(from: $0, in: source) } ?? TypeReference(name: node.text(in: source))
    }

    private func reference(from node: Node, in source: ParsedSource) -> TypeReference {
        switch node.nodeType {
        case "type":
            return node.namedChildren().first.map { reference(from: $0, in: source) }
                ?? TypeReference(name: node.text(in: source))
        case "identifier":
            return TypeReference(name: node.text(in: source))
        case "none":
            return TypeReference(name: "None")
        case "string":
            return TypeReference(name: node.text(in: source).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
        case "attribute", "member_type":
            return TypeReference(name: node.text(in: source).components(separatedBy: ".").last ?? node.text(in: source))
        case "union_type":
            return unionReference(from: node.namedChildren()
                .filter { $0.nodeType == "type" }
                .map { reference(from: $0, in: source) })
        case "binary_operator" where operatorText(node, in: source) == "|":
            let parts = [node.child(byFieldName: "left"), node.child(byFieldName: "right")]
                .compactMap { $0 }
                .map { reference(from: $0, in: source) }
            return unionReference(from: parts)
        case "generic_type":
            return genericReference(node, in: source)
        case "subscript":
            return subscriptReference(node, in: source)
        default:
            return TypeReference(name: node.text(in: source))
        }
    }

    private func operatorText(_ node: Node, in source: ParsedSource) -> String {
        node.child(byFieldName: "operator")?.text(in: source) ?? ""
    }

    private func genericReference(_ node: Node, in source: ParsedSource) -> TypeReference {
        let base = node.namedChildren().first { $0.nodeType == "identifier" }?.text(in: source) ?? node.text(in: source)
        var args: [TypeReference] = []
        for param in node.namedChildren() where param.nodeType == "type_parameter" {
            for arg in param.namedChildren() { args.append(reference(from: arg, in: source)) }
        }
        return composeGeneric(base: base, args: args)
    }

    private func subscriptReference(_ node: Node, in source: ParsedSource) -> TypeReference {
        let base = node.child(byFieldName: "value").map { baseName(from: $0, in: source) } ?? node.text(in: source)
        let args = node.namedChildren().dropFirst().map { reference(from: $0, in: source) }
        return composeGeneric(base: base, args: Array(args))
    }

    /// The simple type name of a base-class/subscript-value expression.
    func baseName(from node: Node, in source: ParsedSource) -> String {
        switch node.nodeType {
        case "identifier":
            return node.text(in: source)
        case "attribute":
            return node.child(byFieldName: "attribute")?.text(in: source) ?? node.text(in: source)
        case "subscript":
            return node.child(byFieldName: "value").map { baseName(from: $0, in: source) } ?? node.text(in: source)
        case "generic_type":
            return node.namedChildren().first { $0.nodeType == "identifier" }?.text(in: source) ?? node.text(in: source)
        default:
            return node.text(in: source)
        }
    }

    private func composeGeneric(base: String, args: [TypeReference]) -> TypeReference {
        switch base {
        case "Optional":
            if var first = args.first {
                first.isOptional = true
                return first
            }
            return TypeReference(name: base)
        case "Union":
            return unionReference(from: args)
        case _ where Self.transparentWrappers.contains(base):
            return args.first ?? TypeReference(name: base)
        default:
            return TypeReference(name: base, genericArguments: args)
        }
    }

    private func unionReference(from args: [TypeReference]) -> TypeReference {
        let hasNone = args.contains { $0.name == "None" }
        let nonNone = args.filter { $0.name != "None" }
        guard var head = nonNone.first else {
            return TypeReference(name: "None", isOptional: hasNone)
        }
        head.isOptional = head.isOptional || hasNone
        head.genericArguments += Array(nonNone.dropFirst())
        return head
    }
}
