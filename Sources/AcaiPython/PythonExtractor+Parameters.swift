import AcaiCore
import AcaiTreeSitter

// MARK: - Call sites

extension PythonExtractor {

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
