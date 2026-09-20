import AcaiCore
import AcaiTreeSitter

/// Python's half of call-site extraction: classify one node, and recognise one local binding.
///
/// The recursion, the scope merging and the ordering all live in `AcaiTreeSitter`'s
/// ``CallSiteResolver``, which holds one of these. Nothing here mutates, so any collaborator that
/// needs a body's call sites can be handed the resolver rather than having to be the extractor.
struct PythonCallSiteSyntax: CallSiteSyntax {

    let context: SourceFileContext

    /// Every type declared in this file, from the pre-pass — a construction of one of these is what
    /// makes a local's type provable.
    let declaredTypeNames: Set<String>

    /// Matches Python `call { function: attribute { object, attribute } }`: `self.method(...)`,
    /// `self.prop.method(...)`, `receiver.method(...)`, and `TypeName.method(...)` (static call).
    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        guard node.nodeType == "call", let funcNode = node.child(byFieldName: "function") else { return nil }

        // Bare call `name(...)`: no receiver type recorded, so the diagram layers resolve it to a
        // top-level function (or drop it, e.g. builtins/constructors).
        if funcNode.nodeType == "identifier" {
            return CallSite(
                receiver: .free, methodName: funcNode.text(in: context), location: node.location(in: context)
            )
        }

        guard funcNode.nodeType == "attribute",
              let attr = funcNode.child(byFieldName: "attribute"),
              let object = funcNode.child(byFieldName: "object") else { return nil }

        let methodName = attr.text(in: context)

        if object.nodeType == "identifier", object.text(in: context) == "self" {
            return CallSite(
                receiver: .selfDispatch, methodName: methodName, location: node.location(in: context)
            )
        }

        var receiverName: String?
        if object.nodeType == "identifier" {
            receiverName = object.text(in: context)
        } else if object.nodeType == "attribute",
                  let innerObject = object.child(byFieldName: "object"),
                  innerObject.nodeType == "identifier", innerObject.text(in: context) == "self",
                  let innerAttr = object.child(byFieldName: "attribute") {
            receiverName = innerAttr.text(in: context)
        }

        guard let name = receiverName else { return nil }
        return scope.resolvedCallSite(
            receiverName: name, methodName: methodName, location: node.location(in: context)
        )
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
            let name = left.text(in: context)
            if let typeField = node.child(byFieldName: "type"),
               let typeId = typeField.firstChild(withType: "identifier") {
                return (name, typeId.text(in: context))
            }
            guard let right = node.child(byFieldName: "right"), right.nodeType == "call",
                  let function = right.child(byFieldName: "function")
            else { return nil }
            if function.nodeType == "identifier", declaredTypeNames.contains(function.text(in: context)) {
                return (name, function.text(in: context))
            }
            if function.nodeType == "attribute",
               let object = function.child(byFieldName: "object"), object.nodeType == "identifier",
               object.text(in: context) == "self",
               let attr = function.child(byFieldName: "attribute"),
               let returnType = scope.knownMethodReturnTypes[attr.text(in: context)] {
                return (name, returnType)
            }
            return nil
        }
    }
}
