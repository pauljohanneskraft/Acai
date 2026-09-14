import AcaiCore
import AcaiTreeSitter

// MARK: - PythonParameterExtractor

/// Parses a Python parameter list into `Parameter` values (positional, defaulted, typed, and
/// `*args`/`**kwargs` splats). Stateless beyond `context`, mirroring `PythonBaseClassResolver`.
struct PythonParameterExtractor {
    let context: SourceFileContext

    func parameters(_ node: Node) -> [Parameter] {
        let resolver = PythonTypeReferenceResolver(context: context)
        var params: [Parameter] = []
        for child in node.namedChildren() {
            switch child.nodeType {
            case "identifier":
                params.append(Parameter(internalName: child.text(in: context)))
            case "typed_parameter":
                params.append(typedParameter(child, resolver: resolver))
            case "default_parameter":
                let name = child.child(byFieldName: "name").map { $0.text(in: context) } ?? ""
                let def = child.child(byFieldName: "value").map { $0.text(in: context) }
                params.append(Parameter(internalName: name, defaultValue: def))
            case "typed_default_parameter":
                let name = child.child(byFieldName: "name").map { $0.text(in: context) } ?? ""
                let type = child.child(byFieldName: "type").flatMap { resolver.resolve(fromTypeField: $0) }
                let def = child.child(byFieldName: "value").map { $0.text(in: context) }
                params.append(Parameter(internalName: name, type: type, defaultValue: def))
            case "list_splat_pattern", "dictionary_splat_pattern":
                params.append(Parameter(internalName: splatName(child), isVariadic: true))
            default:
                break // keyword_separator (`*`), positional_separator (`/`), tuple_pattern
            }
        }
        return params
    }

    private func typedParameter(_ node: Node, resolver: PythonTypeReferenceResolver) -> Parameter {
        // The name is the non-`type` child: a bare identifier, or a `*args`/`**kwargs` splat.
        let nameChild = node.namedChildren().first { $0.nodeType != "type" }
        let isVariadic = nameChild.map {
            $0.nodeType == "list_splat_pattern" || $0.nodeType == "dictionary_splat_pattern"
        } ?? false
        let name = nameChild.map { splatName($0) } ?? ""
        let type = node.child(byFieldName: "type").flatMap { resolver.resolve(fromTypeField: $0) }
        return Parameter(internalName: name, type: type, isVariadic: isVariadic)
    }

    private func splatName(_ node: Node) -> String {
        if node.nodeType == "identifier" { return node.text(in: context) }
        return node.namedChildren().first { $0.nodeType == "identifier" }.map { $0.text(in: context) }
            ?? node.text(in: context)
    }
}

extension PythonExtractor {
    var parameterExtractor: PythonParameterExtractor { PythonParameterExtractor(context: context) }
}
