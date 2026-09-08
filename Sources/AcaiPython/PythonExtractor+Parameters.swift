import AcaiCore
import AcaiTreeSitter

// MARK: - Parameters & call sites

extension PythonExtractor {

    // MARK: - Parameters

    func extractParameters(_ node: Node) -> [Parameter] {
        var params: [Parameter] = []
        for child in node.namedChildren() {
            switch child.nodeType {
            case "identifier":
                params.append(Parameter(internalName: text(child)))
            case "typed_parameter":
                params.append(extractTypedParameter(child))
            case "default_parameter":
                let name = child.child(byFieldName: "name").map { text($0) } ?? ""
                let def = child.child(byFieldName: "value").map { text($0) }
                params.append(Parameter(internalName: name, defaultValue: def))
            case "typed_default_parameter":
                let name = child.child(byFieldName: "name").map { text($0) } ?? ""
                let type = child.child(byFieldName: "type").flatMap { typeReferenceResolver.resolve(fromTypeField: $0) }
                let def = child.child(byFieldName: "value").map { text($0) }
                params.append(Parameter(internalName: name, type: type, defaultValue: def))
            case "list_splat_pattern", "dictionary_splat_pattern":
                params.append(Parameter(internalName: splatName(child), isVariadic: true))
            default:
                break // keyword_separator (`*`), positional_separator (`/`), tuple_pattern
            }
        }
        return params
    }

    private func extractTypedParameter(_ node: Node) -> Parameter {
        // The name is the non-`type` child: a bare identifier, or a `*args`/`**kwargs` splat.
        let nameChild = node.namedChildren().first { $0.nodeType != "type" }
        let isVariadic = nameChild.map {
            $0.nodeType == "list_splat_pattern" || $0.nodeType == "dictionary_splat_pattern"
        } ?? false
        let name = nameChild.map { splatName($0) } ?? ""
        let type = node.child(byFieldName: "type").flatMap { typeReferenceResolver.resolve(fromTypeField: $0) }
        return Parameter(internalName: name, type: type, isVariadic: isVariadic)
    }

    private func splatName(_ node: Node) -> String {
        if node.nodeType == "identifier" { return text(node) }
        return node.namedChildren().first { $0.nodeType == "identifier" }.map { text($0) } ?? text(node)
    }

    // MARK: - Call sites

    /// Matches Python `call { function: attribute { object, attribute } }`: `self.method(...)`,
    /// `self.prop.method(...)`, `receiver.method(...)`, and `TypeName.method(...)` (static call).
    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        guard node.nodeType == "call", let funcNode = node.child(byFieldName: "function") else { return nil }

        // Bare call `name(...)`: no receiver type recorded, so the diagram layers resolve it to a
        // top-level function (or drop it, e.g. builtins/constructors).
        if funcNode.nodeType == "identifier" {
            return CallSite(receiver: .free, methodName: text(funcNode), location: loc(node))
        }

        guard funcNode.nodeType == "attribute",
              let attr = funcNode.child(byFieldName: "attribute"),
              let object = funcNode.child(byFieldName: "object") else { return nil }

        let methodName = text(attr)

        if object.nodeType == "identifier", text(object) == "self" {
            return CallSite(receiver: .selfDispatch, methodName: methodName, location: loc(node))
        }

        var receiverName: String?
        if object.nodeType == "identifier" {
            receiverName = text(object)
        } else if object.nodeType == "attribute",
                  let innerObject = object.child(byFieldName: "object"),
                  innerObject.nodeType == "identifier", text(innerObject) == "self",
                  let innerAttr = object.child(byFieldName: "attribute") {
            receiverName = text(innerAttr)
        }

        guard let name = receiverName else { return nil }
        return scope.resolvedCallSite(receiverName: name, methodName: methodName, location: loc(node))
    }

    /// Provable local-variable types: an explicit annotation, a `Foo()` construction of a declared
    /// type, or (Python requires an explicit receiver) a same-type call `x = self.compute()` with an
    /// unambiguous return type. `self.x = …` targets an `attribute` node, not `identifier`, so it's
    /// left to field synthesis.
    func localBindings(in body: Node, scope: CallSiteScope) -> [String: String] {
        collectLocalBindings(in: body) { node in
            guard node.nodeType == "assignment",
                  let left = node.child(byFieldName: "left"), left.nodeType == "identifier"
            else { return nil }
            let name = text(left)
            if let typeField = node.child(byFieldName: "type"),
               let typeId = typeField.firstChild(withType: "identifier") {
                return (name, text(typeId))
            }
            guard let right = node.child(byFieldName: "right"), right.nodeType == "call",
                  let function = right.child(byFieldName: "function")
            else { return nil }
            if function.nodeType == "identifier", declaredTypeNames.contains(text(function)) {
                return (name, text(function))
            }
            if function.nodeType == "attribute",
               let object = function.child(byFieldName: "object"), object.nodeType == "identifier",
               text(object) == "self",
               let attr = function.child(byFieldName: "attribute"),
               let returnType = scope.knownMethodReturnTypes[text(attr)] {
                return (name, returnType)
            }
            return nil
        }
    }
}
