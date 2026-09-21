import AcaiCore
import AcaiTreeSitter

// MARK: - JSParameterExtractor

/// Parses a JS/TS parameter list into `Parameter` values (plain, TypeScript-annotated, defaulted,
/// rest/splat and destructuring parameters).
struct JSParameterExtractor {
    let context: SourceFileContext
    let isTypeScript: Bool
    let typeReferences: JSTypeReferenceResolver

    func parameters(_ node: Node) -> [Parameter] {
        var params: [Parameter] = []
        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            switch childType {
            case "formal_parameter", "required_parameter", "optional_parameter":
                params.append(singleParameter(child, isOptional: childType == "optional_parameter"))
            case "rest_pattern", "rest_element":
                var param = restParameter(child)
                param.isVariadic = true
                params.append(param)
            case "identifier":
                params.append(Parameter(internalName: child.text(in: context)))
            case "assignment_pattern":
                params.append(assignmentParameter(child))
            case "destructuring_pattern", "array_pattern", "object_pattern":
                params.append(Parameter(internalName: child.text(in: context)))
            default:
                break
            }
        }
        return params
    }

    private func singleParameter(_ node: Node, isOptional: Bool) -> Parameter {
        let name: String
        if let patternNode = node.child(byFieldName: "pattern") {
            name = patternNode.text(in: context)
        } else {
            name = parameterName(node)
        }

        var paramType: TypeReference?
        if isTypeScript {
            paramType = typeReferences.extractTypeAnnotation(node)
        }

        if isOptional { paramType?.isOptional = true }

        let defaultValue: String? = node.child(byFieldName: "value").map { $0.text(in: context) }

        var modifiers: [Modifier] = []
        if node.hasDirectChildText("readonly", in: context) {
            modifiers.append(.readonly)
        }

        return Parameter(internalName: name, type: paramType, defaultValue: defaultValue, modifiers: modifiers)
    }

    private func restParameter(_ node: Node) -> Parameter {
        var name = ""
        for child in node.namedChildren() where child.nodeType == "identifier" {
            name = child.text(in: context)
            break
        }
        if name.isEmpty {
            if let patternNode = node.child(byFieldName: "pattern") {
                name = patternNode.text(in: context)
            } else {
                name = node.text(in: context).replacingOccurrences(of: "...", with: "")
            }
        }

        var paramType: TypeReference?
        if isTypeScript { paramType = typeReferences.extractTypeAnnotation(node) }

        return Parameter(internalName: name, type: paramType, isVariadic: true)
    }

    private func assignmentParameter(_ node: Node) -> Parameter {
        let name = node.child(byFieldName: "left").map { $0.text(in: context) } ?? ""
        let defaultValue = node.child(byFieldName: "right").map { $0.text(in: context) }
        return Parameter(internalName: name, defaultValue: defaultValue)
    }

    func parameterName(_ node: Node) -> String {
        if let pattern = node.child(byFieldName: "pattern") {
            return pattern.text(in: context)
        }
        for child in node.children() where child.nodeType == "identifier" {
            return child.text(in: context)
        }
        return ""
    }
}
