import Foundation
import AcaiCore
import AcaiTreeSitter

// MARK: - DartParameterExtractor

/// Parses a Dart `formal_parameter_list` — positional, optional positional and named parameters,
/// and `this.x` field-formal parameters — into `Parameter` values.
struct DartParameterExtractor {
    let context: SourceFileContext
    let typeReferences: DartTypeReferenceResolver

    func parameters(_ node: Node) -> [Parameter] {
        var params: [Parameter] = []
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "formal_parameter", "normal_formal_parameter":
                if let parameter = formalParameter(child) { params.append(parameter) }
            case "default_formal_parameter":
                if let parameter = defaultFormalParameter(child) { params.append(parameter) }
            case "optional_positional_formal_parameters", "optional_named_formal_parameters":
                params.append(contentsOf: optionalParameters(child))
            default:
                break
            }
        }
        return params
    }

    private func optionalParameters(_ node: Node) -> [Parameter] {
        var params: [Parameter] = []
        for innerChild in node.children() {
            guard let childType = innerChild.nodeType,
                  childType == "default_formal_parameter"
                    || childType == "formal_parameter"
                    || childType == "normal_formal_parameter" else { continue }
            if let parameter = defaultFormalParameter(innerChild)
                ?? formalParameter(innerChild) {
                params.append(parameter)
            }
        }
        return params
    }

    private func fieldFormalParameter(_ fullText: String) -> Parameter? {
        guard fullText.contains("this.") else { return nil }
        let parts = fullText.components(separatedBy: "this.")
        guard parts.count >= 2 else { return nil }
        let afterThis = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let paramName = afterThis
            .components(separatedBy: CharacterSet.alphanumerics.inverted).first ?? afterThis
        return Parameter(internalName: paramName, type: nil)
    }

    private func apply(
        _ child: Node, childType: String,
        paramType: inout TypeReference?, name: inout String, modifiers: inout [Modifier]
    ) {
        switch childType {
        case "identifier":
            let childText = child.text(in: context)
            if paramType == nil && name.isEmpty {
                name = childText
            } else if !name.isEmpty && paramType == nil {
                paramType = TypeReference(name: name)
                name = childText
            } else {
                name = childText
            }
        case "type_identifier", "generic_type", "function_type", "void_type":
            paramType = typeReferences.typeReference(child)
        case "final_builtin":
            modifiers.append(.final)
        case "covariant":
            modifiers.append(.covariant)
        case "required":
            modifiers.append(.required)
        default:
            if paramType == nil, let ref = typeReferences.typeReference(child) {
                paramType = ref
            }
        }
    }

    private func formalParameter(_ node: Node) -> Parameter? {
        if let fieldParam = fieldFormalParameter(node.text(in: context)) {
            return fieldParam
        }
        var paramType: TypeReference?
        var name = ""
        var modifiers: [Modifier] = []
        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            apply(child, childType: childType, paramType: &paramType, name: &name, modifiers: &modifiers)
        }
        guard !name.isEmpty else { return nil }
        return Parameter(internalName: name, type: paramType, modifiers: modifiers)
    }

    private func defaultFormalParameter(_ node: Node) -> Parameter? {
        for child in node.children() {
            if child.nodeType == "formal_parameter" || child.nodeType == "normal_formal_parameter" {
                return formalParameter(child)
            }
        }
        return formalParameter(node)
    }
}
