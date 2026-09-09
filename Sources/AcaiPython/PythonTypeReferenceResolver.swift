import Foundation
import AcaiCore
import AcaiTreeSitter

// MARK: - PythonTypeReferenceResolver

/// Resolves a Python type-annotation node into a `TypeReference`: PEP 604 unions (`X | Y`),
/// `Optional[X]`/`Union[...]` subscripts, PEP 695 generics, forward references (`"User"`), and the
/// stdlib's transparent wrappers (`Final`, `ClassVar`, `Annotated`) are all collapsed to the single
/// shape the diagram layer expects. Stateless beyond `context`, which it only needs to read node text.
struct PythonTypeReferenceResolver {
    let context: SourceFileContext

    private static let transparentWrappers: Set<String> = ["Final", "ClassVar", "Annotated"]

    /// Unwraps a `type` field node to the annotation it carries.
    func resolve(fromTypeField node: Node) -> TypeReference? {
        let inner = (node.nodeType == "type") ? node.namedChildren().first : node
        return inner.map { reference(from: $0) }
    }

    /// A superclass expression's base name: a plain identifier, a dotted `module.Attr` access, or a
    /// subscripted/generic base (`Generic[T]`).
    func baseTypeName(from node: Node) -> String? {
        switch node.nodeType {
        case "identifier":
            return node.text(in: context)
        case "attribute":
            return node.child(byFieldName: "attribute").map { $0.text(in: context) }
        case "subscript":
            return node.child(byFieldName: "value").flatMap { baseTypeName(from: $0) }
        case "generic_type":
            return node.namedChildren().first { $0.nodeType == "identifier" }.map { $0.text(in: context) }
        default:
            return nil
        }
    }

    private func reference(from node: Node) -> TypeReference {
        switch node.nodeType {
        case "type":
            return node.namedChildren().first.map { reference(from: $0) }
                ?? TypeReference(name: node.text(in: context))
        case "identifier":
            return TypeReference(name: node.text(in: context))
        case "none":
            return TypeReference(name: "None")
        case "string":
            // Forward reference, e.g. `"User"`.
            return TypeReference(
                name: node.text(in: context).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            )
        case "attribute", "member_type":
            let text = node.text(in: context)
            return TypeReference(name: text.components(separatedBy: ".").last ?? text)
        case "union_type":
            return unionReference(from: node.namedChildren()
                .filter { $0.nodeType == "type" }
                .map { reference(from: $0) })
        case "binary_operator" where binaryOperatorText(node) == "|":
            // PEP 604 union written with the bitwise-or operator, e.g. `str | None`.
            let parts = [node.child(byFieldName: "left"), node.child(byFieldName: "right")]
                .compactMap { $0 }
                .map { reference(from: $0) }
            return unionReference(from: parts)
        case "generic_type":
            return genericReference(node)
        case "subscript":
            return subscriptReference(node)
        default:
            return TypeReference(name: node.text(in: context))
        }
    }

    private func binaryOperatorText(_ node: Node) -> String {
        node.child(byFieldName: "operator").map { $0.text(in: context) } ?? ""
    }

    private func genericReference(_ node: Node) -> TypeReference {
        let base = node.namedChildren().first { $0.nodeType == "identifier" }
            .map { $0.text(in: context) } ?? node.text(in: context)
        var args: [TypeReference] = []
        for param in node.namedChildren() where param.nodeType == "type_parameter" {
            for arg in param.namedChildren() {
                args.append(reference(from: arg))
            }
        }
        return composeGeneric(base: base, args: args)
    }

    private func subscriptReference(_ node: Node) -> TypeReference {
        let base = node.child(byFieldName: "value").flatMap { baseTypeName(from: $0) } ?? node.text(in: context)
        let args = node.namedChildren().dropFirst().map { reference(from: $0) }
        return composeGeneric(base: base, args: Array(args))
    }

    /// `Optional[X]` sets `isOptional`; `Union[...]` collapses like a `|` union; the stdlib's
    /// transparent wrappers unwrap to their single argument so they never appear as phantom diagram
    /// nodes; anything else composes into a generic reference.
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

    /// Collapses a union (`X | Y | None`) to a single reference: a `None` member marks it optional;
    /// any further members are kept as generic arguments so the enrichment pass still draws edges.
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

extension PythonExtractor {
    var typeReferenceResolver: PythonTypeReferenceResolver {
        PythonTypeReferenceResolver(context: context)
    }
}
