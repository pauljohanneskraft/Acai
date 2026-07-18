import Foundation
import AcaiCore
import AcaiTreeSitter

// MARK: - Declarators, type references, parameters

/// The salient facts about a C/C++ declarator, recovered by unwrapping the pointer / reference /
/// array / function layers the grammar nests around the declared name.
struct CFamilyDeclarator {
    var name = ""
    var isFunction = false
    var parameters: [Parameter] = []
    var isArray = false
}

extension CFamilyExtractor {

    private static let declaratorNodeTypes: Set<String> = [
        "identifier", "field_identifier", "type_identifier", "qualified_identifier",
        "pointer_declarator", "reference_declarator", "array_declarator", "function_declarator",
        "parenthesized_declarator", "init_declarator", "operator_name", "destructor_name",
        "operator_cast", "template_function"
    ]

    /// Recursively unwraps a declarator into its name + function/array facts.
    func parseDeclarator(_ node: Node?) -> CFamilyDeclarator {
        guard let node, let nodeType = node.nodeType else { return CFamilyDeclarator() }
        switch nodeType {
        case "identifier", "field_identifier", "type_identifier", "namespace_identifier",
             "operator_name", "destructor_name", "qualified_identifier", "template_function":
            return CFamilyDeclarator(name: text(node))
        case "function_declarator":
            var info = parseDeclarator(node.child(byFieldName: "declarator"))
            info.isFunction = true
            info.parameters = parseParameterList(node.child(byFieldName: "parameters"))
            return info
        case "array_declarator":
            var info = parseDeclarator(childDeclarator(of: node))
            info.isArray = true
            return info
        case "pointer_declarator", "reference_declarator", "parenthesized_declarator":
            return parseDeclarator(childDeclarator(of: node))
        case "init_declarator":
            return parseDeclarator(node.child(byFieldName: "declarator"))
        default:
            return CFamilyDeclarator(name: text(node))
        }
    }

    private func childDeclarator(of node: Node) -> Node? {
        node.child(byFieldName: "declarator")
            ?? node.namedChildren().first { Self.declaratorNodeTypes.contains($0.nodeType ?? "") }
    }

    // MARK: - Parameters

    func parseParameterList(_ node: Node?) -> [Parameter] {
        guard let node else { return [] }
        var parameters: [Parameter] = []
        for child in node.namedChildren() {
            switch child.nodeType {
            case "parameter_declaration", "optional_parameter_declaration":
                if let parameter = parseParameter(child) { parameters.append(parameter) }
            case "variadic_parameter_declaration":
                parameters.append(Parameter(internalName: "...", isVariadic: true))
            default:
                break
            }
        }
        return parameters
    }

    private func parseParameter(_ node: Node) -> Parameter? {
        let declarator = parseDeclarator(node.child(byFieldName: "declarator"))
        let typeRef = typeReference(from: node.child(byFieldName: "type"), declarator: declarator)
        let name = lastComponent(of: declarator.name)
        // A declarator-less, type-only parameter (`void f(int)`) has no name; skip empty/`void`.
        if name.isEmpty, typeRef == nil || typeRef?.name == "void" { return nil }
        return Parameter(internalName: name.isEmpty ? "_" : name, type: typeRef)
    }

    // MARK: - Type references

    /// Builds a `TypeReference` from a declaration's `type` node, folding in array-ness from the
    /// declarator so collection edges are inferred for `Foo bar[]`.
    func typeReference(from typeNode: Node?, declarator: CFamilyDeclarator) -> TypeReference? {
        guard let typeNode, var ref = baseTypeReference(typeNode) else { return nil }
        if declarator.isArray {
            ref = TypeReference(
                name: ref.name, genericArguments: ref.genericArguments,
                isOptional: ref.isOptional, isArray: true
            )
        }
        return ref
    }

    func baseTypeReference(_ node: Node) -> TypeReference? {
        switch node.nodeType {
        case "struct_specifier", "union_specifier", "enum_specifier", "class_specifier":
            return node.child(byFieldName: "name").map { TypeReference(name: text($0)) }
        default:
            return genericTypeReference(node)
        }
    }

    /// Builds a `TypeReference` from any non-record type node. A template (`std::vector<Player>`,
    /// `qualified_identifier` wrapping a `template_type`, …) is split at the first `<` into its base
    /// name (`std::vector`, matched against `collectionTypeNames`) and its arguments (`Player`).
    private func genericTypeReference(_ node: Node) -> TypeReference? {
        let full = normalizeWhitespace(text(node))
        guard !full.isEmpty else { return nil }
        guard let angle = full.firstIndex(of: "<") else {
            return TypeReference(name: full)
        }
        let base = String(full[..<angle]).trimmingCharacters(in: .whitespaces)
        return TypeReference(name: base, genericArguments: templateArguments(under: node))
    }

    private func templateArguments(under node: Node) -> [TypeReference] {
        guard let list = firstDescendant(of: node, nodeType: "template_argument_list") else { return [] }
        var arguments: [TypeReference] = []
        for arg in list.namedChildren() {
            // A template argument is usually a `type_descriptor` wrapping the type, but the grammar
            // also yields bare type nodes; handle both.
            let typeNode = arg.nodeType == "type_descriptor"
                ? (arg.child(byFieldName: "type") ?? arg.namedChildren().first)
                : arg
            if let typeNode, let ref = baseTypeReference(typeNode) {
                arguments.append(ref)
            }
        }
        return arguments
    }

    private func firstDescendant(of node: Node, nodeType: String) -> Node? {
        for child in node.namedChildren() {
            if child.nodeType == nodeType { return child }
            if let found = firstDescendant(of: child, nodeType: nodeType) { return found }
        }
        return nil
    }

    // MARK: - Template parameters

    /// Generic parameters declared by a `template_declaration` (`template <typename T, class U>`).
    func templateParameters(_ node: Node) -> [GenericParameter] {
        guard let list = node.child(byFieldName: "parameters") else { return [] }
        var parameters: [GenericParameter] = []
        for child in list.namedChildren() {
            switch child.nodeType {
            case "type_parameter_declaration", "optional_type_parameter_declaration",
                 "variadic_type_parameter_declaration":
                if let nameNode = child.namedChildren().first(where: { $0.nodeType == "type_identifier" }) {
                    parameters.append(GenericParameter(name: text(nameNode)))
                }
            case "parameter_declaration", "optional_parameter_declaration":
                let info = parseDeclarator(child.child(byFieldName: "declarator"))
                if !info.name.isEmpty { parameters.append(GenericParameter(name: info.name)) }
            default:
                break
            }
        }
        return parameters
    }

    // MARK: - Helpers

    /// The final component of a possibly-qualified name (`std::string` → `string`, `Foo::bar` → `bar`).
    func lastComponent(of name: String) -> String {
        guard let range = name.range(of: "::", options: .backwards) else { return name }
        return String(name[range.upperBound...])
    }

    func normalizeWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .joined(separator: " ")
    }
}
