import AcaiCore
import AcaiTreeSitter

// MARK: - JavaParameterExtractor

/// Parses a Java formal-parameter list, a record's component list, and enum-constant argument
/// lists into `Parameter` values.
struct JavaParameterExtractor {
    let context: SourceFileContext
    let typeReferences: JavaTypeReferenceResolver
    let modifiers: JavaModifiers

    func parameters(_ node: Node) -> [Parameter] {
        var params: [Parameter] = []
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "formal_parameter":
                if let param = parameter(child) { params.append(param) }
            case "spread_parameter":
                if let param = spreadParameter(child) { params.append(param) }
            case "receiver_parameter":
                break // Skip 'this' parameter
            default:
                break
            }
        }
        return params
    }

    func parameter(_ node: Node) -> Parameter? {
        var paramType: TypeReference?
        var name = ""
        var paramModifiers: [Modifier] = []

        if let modNode = node.firstChild(withType: "modifiers") {
            paramModifiers = modifiers.info(for: modNode).modifiers
        }

        if let typeNode = node.child(byFieldName: "type") { paramType = typeReferences.extractTypeReference(typeNode) }
        if let nameNode = node.child(byFieldName: "name") { name = nameNode.text(in: context) }
        guard !name.isEmpty else { return nil }

        if let dimensionsNode = node.child(byFieldName: "dimensions") {
            let dimText = dimensionsNode.text(in: context)
            if !dimText.isEmpty, let parameterType = paramType {
                paramType = TypeReference(
                    name: parameterType.name, genericArguments: parameterType.genericArguments,
                    isOptional: parameterType.isOptional, isArray: true
                )
            }
        }

        return Parameter(internalName: name, type: paramType, modifiers: paramModifiers)
    }

    private func spreadParameter(_ node: Node) -> Parameter? {
        var paramType: TypeReference?
        var name = ""
        if let typeNode = node.child(byFieldName: "type") { paramType = typeReferences.extractTypeReference(typeNode) }
        if let nameNode = node.child(byFieldName: "name") { name = nameNode.text(in: context) }
        // Fallback: last named child is usually the name in varargs
        if name.isEmpty, let lastNamed = node.namedChildren().last { name = lastNamed.text(in: context) }
        guard !name.isEmpty else { return nil }
        return Parameter(internalName: name, type: paramType, isVariadic: true)
    }

    // MARK: - Record Components

    func recordComponents(_ node: Node) -> [Parameter] {
        var params: [Parameter] = []
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "formal_parameter" || nodeType == "spread_parameter" {
                if let param = parameter(child) { params.append(param) }
            }
        }
        return params
    }

    // MARK: - Enum Constant Arguments

    /// Every argument recorded as a raw-text `Parameter` — enum-constant arguments aren't typed.
    func argumentsAsParameters(_ node: Node) -> [Parameter] {
        node.namedChildren().compactMap { child in
            let argText = child.text(in: context)
            return argText.isEmpty ? nil : Parameter(internalName: argText)
        }
    }
}
