import Foundation
import UMLCore
import UMLTreeSitter

extension RustExtractor {
    func extractTypeReference(_ node: Node) -> TypeReference? {
        switch node.nodeType {
        case "type_identifier", "identifier", "primitive_type":
            return TypeReference(name: text(node))
        case "reference_type":
            return node.child(byFieldName: "type").flatMap(extractTypeReference)
        case "generic_type":
            guard let baseNode = node.child(byFieldName: "type"),
                  let baseType = extractTypeReference(baseNode) else { return nil }
            let arguments = node.child(byFieldName: "type_arguments")?.namedChildren().compactMap {
                extractTypeReference($0)
            } ?? []
            if baseType.name == "Option", let wrapped = arguments.first {
                return TypeReference(
                    name: wrapped.name,
                    genericArguments: wrapped.genericArguments,
                    isOptional: true,
                    isArray: wrapped.isArray
                )
            }
            return TypeReference(
                name: baseType.name,
                genericArguments: arguments,
                isArray: ["Vec", "VecDeque", "LinkedList", "BinaryHeap"].contains(baseType.name)
            )
        case "array_type":
            guard let element = node.child(byFieldName: "element").flatMap(extractTypeReference) else { return nil }
            return TypeReference(
                name: element.name,
                genericArguments: element.genericArguments,
                isOptional: element.isOptional,
                isArray: true
            )
        case "scoped_type_identifier", "scoped_identifier":
            return node.child(byFieldName: "name").map { TypeReference(name: text($0)) }
        case "tuple_type", "function_type":
            return TypeReference(name: text(node))
        default:
            let name = simpleTypeName(from: text(node))
            return name.isEmpty ? nil : TypeReference(name: name)
        }
    }

    func extractGenericParameters(from node: Node?) -> [GenericParameter] {
        guard let node else { return [] }
        return node.namedChildren().compactMap { child in
            switch child.nodeType {
            case "type_parameter":
                guard let nameNode = child.child(byFieldName: "name") else { return nil }
                return GenericParameter(
                    name: text(nameNode),
                    constraints: extractConstraints(from: child.child(byFieldName: "bounds"))
                )
            case "const_parameter":
                guard let nameNode = child.child(byFieldName: "name") else { return nil }
                return GenericParameter(name: text(nameNode))
            default:
                return nil
            }
        }
    }

    func extractConstraints(from node: Node?) -> [GenericConstraint] {
        guard let node else { return [] }
        return node.namedChildren().compactMap { child in
            extractTypeReference(child).map { GenericConstraint(kind: .conformance, type: $0) }
        }
    }

    func extractTraitBounds(from node: Node?) -> [TypeReference] {
        guard let node else { return [] }
        return node.namedChildren().compactMap(extractTypeReference)
    }

    func extractAssociatedType(from node: Node) -> GenericParameter? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        return GenericParameter(
            name: text(nameNode),
            constraints: extractConstraints(from: node.child(byFieldName: "bounds"))
        )
    }

    func extractAttributes(from node: Node) -> [String] {
        node.namedChildren()
            .filter { $0.nodeType == "attribute_item" }
            .map { text($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func accessLevel(for node: Node, default defaultAccessLevel: AccessLevel) -> AccessLevel {
        guard let visibility = node.firstChild(withType: "visibility_modifier") else {
            return defaultAccessLevel
        }
        let visibilityText = text(visibility).replacingOccurrences(of: " ", with: "")
        switch visibilityText {
        case "pub":
            return .public
        case "pub(crate)":
            return .packagePrivate
        case "pub(super)":
            return .protected
        case "pub(self)":
            return .private
        default:
            return .internal
        }
    }

    func simpleTypeName(from raw: String) -> String {
        let withoutGenerics = raw.split(separator: "<", maxSplits: 1).first.map(String.init) ?? raw
        let withoutReference = withoutGenerics
            .replacingOccurrences(of: "&", with: "")
            .replacingOccurrences(of: "mut ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pathSeparated = withoutReference.components(separatedBy: "::")
        return pathSeparated.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? withoutReference
    }

    func parameterName(from raw: String) -> String? {
        let trimmed = raw
            .replacingOccurrences(of: "mut ", with: "")
            .replacingOccurrences(of: "&", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.components(separatedBy: CharacterSet.alphanumerics.inverted.union(CharacterSet(charactersIn: "_")).inverted.inverted)
        return components.last(where: { !$0.isEmpty })
    }

    func implTargetName(from node: Node) -> String? {
        guard let typeReference = extractTypeReference(node) else { return nil }
        if text(node).contains("::") {
            return text(node)
                .split(separator: "<", maxSplits: 1)
                .first
                .map { String($0).replacingOccurrences(of: "::", with: ".") }
        }
        return qualifiedName(typeReference.name)
    }
}
