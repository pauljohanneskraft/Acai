import AcaiCore
import AcaiTreeSitter

struct PythonCallSiteSyntax: CallSiteSyntax {

    let context: SourceFileContext

    /// From the pre-pass: constructing one of these is what makes a local's type provable.
    let declaredTypeNames: Set<String>

    /// A capitalised bare call to one of these is a call, not a construction of a class from elsewhere.
    let declaredFunctionNames: Set<String>

    private static let memberCallGrammar = MemberCallGrammar(
        selfIdentifier: "self", memberAccessType: "attribute", memberField: "attribute"
    )

    /// Matches Python `call { function: attribute { object, attribute } }`: `self.method(...)`,
    /// `self.prop.method(...)`, `receiver.method(...)`, `TypeName.method(...)` (static call), and
    /// `head.hop.method(...)` — a deferred `.propertyChain` where the head resolves.
    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        guard node.nodeType == "call", let funcNode = node.child(byFieldName: "function") else { return nil }

        // Bare call `name(...)`: a declared or capitalised type name is a construction targeting the
        // class's fixed `__init__` member — speculative unless declared in-file, so a library class
        // (`Path()`) stays out of coverage. Anything else records no receiver type, so the diagram
        // layers resolve it to a top-level function or drop it (e.g. a builtin); Python has no
        // implicit receiver, so it stays `.free` rather than `.selfDispatch`.
        if funcNode.nodeType == "identifier" {
            let name = funcNode.text(in: context)
            let location = node.location(in: context)
            guard !declaredFunctionNames.contains(name),
                  let construction = scope.constructionCallSite(
                    typeName: name, methodName: "__init__", location: location)
            else {
                return scope.bareCall(
                    named: name, implicitSelf: false, constructorMethodName: { _ in "__init__" }, location: location)
            }
            return construction
        }

        guard funcNode.nodeType == "attribute",
              let attr = funcNode.child(byFieldName: "attribute"),
              let object = funcNode.child(byFieldName: "object") else { return nil }

        return MemberCallResolver(context: context, grammar: Self.memberCallGrammar).callSite(
            receiver: object,
            methodName: attr.text(in: context),
            scope: scope,
            location: node.location(in: context)
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
