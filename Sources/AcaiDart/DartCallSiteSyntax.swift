import AcaiCore
import AcaiTreeSitter

struct DartCallSiteSyntax: CallSiteSyntax {

    let context: SourceFileContext

    /// From the pre-pass: constructing one of these is what makes a local's type provable.
    let declaredTypeNames: Set<String>

    /// Resolves statically-determinable Dart call patterns: `receiver.method(args)` where
    /// `receiver` is a known property, `this.method(args)`, or `TypeName.method(args)` (static call).
    ///
    /// The Dart grammar flattens `receiver.method(args)` into siblings — `receiver`, a `selector`
    /// carrying the method name, a trailing `selector` carrying `argument_part`. Only that
    /// three-part shape is matched; chains like `a.b.c()` have an extra selector and are skipped.
    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        // `field = callee(args)` flattens as siblings [field-id, callee-id, selector(argument_part)]
        // inside `field_initializer` or `initialized_identifier`. The guard drops constructions
        // `Foo()` and non-call initializers.
        if node.nodeType == "field_initializer" || node.nodeType == "initialized_identifier" {
            let kids = node.namedChildren()
            guard kids.count >= 2,
                  kids[kids.count - 1].nodeType == "selector",
                  kids[kids.count - 1].firstChild(withType: "argument_part") != nil,
                  kids[kids.count - 2].nodeType == "identifier"
            else { return nil }
            return scope.bareCall(
                named: kids[kids.count - 2].text(in: context), implicitSelf: true, location: node.location(in: context)
            )
        }

        let named = node.namedChildren()

        // Bare `foo(args)`: implicit `this.foo()` or a top-level function, tagged `.selfDispatch` so
        // the call-graph builder can fall back to a free function. `bareCall`'s `knownTypeNames`
        // guard drops constructor calls `Foo()`, which share this shape.
        if named.count == 2,
           named[0].nodeType == "identifier",
           named[1].nodeType == "selector",
           named[1].firstChild(withType: "argument_part") != nil {
            return scope.bareCall(
                named: named[0].text(in: context), implicitSelf: true, location: node.location(in: context)
            )
        }

        guard named.count == 3 else { return nil }

        let receiverNode = named[0]
        let methodSelector = named[1]
        let argsSelector = named[2]

        guard methodSelector.nodeType == "selector",
              argsSelector.nodeType == "selector",
              argsSelector.firstChild(withType: "argument_part") != nil,
              let assignable = methodSelector.firstChild(withType: "unconditional_assignable_selector"),
              let methodId = assignable.firstChild(withType: "identifier")
        else { return nil }

        let methodName = methodId.text(in: context)

        if receiverNode.nodeType == "this" {
            return CallSite(receiver: .selfDispatch, methodName: methodName, location: node.location(in: context))
        }

        guard receiverNode.nodeType == "identifier" else { return nil }
        return scope.resolvedCallSite(
            receiverName: receiverNode.text(in: context),
            methodName: methodName,
            location: node.location(in: context)
        )
    }

    /// Provable local-variable types: an explicit annotation (`Helper h = …`), an inferred
    /// construction (`var h = Helper()`) of a declared type, or a same-type method call with an
    /// unambiguous return type (`var h = compute()`, via `scope.knownMethodReturnTypes`), so
    /// `h.method()` resolves to `Helper`.
    func localBindings(in body: Node, scope: CallSiteScope) -> [String: String] {
        collectLocalBindings(in: body) { node in
            guard node.nodeType == "initialized_variable_definition",
                  let nameNode = node.child(byFieldName: "name")
            else { return nil }
            let name = nameNode.text(in: context)
            if let typeId = node.firstChild(withType: "type_identifier") {
                return (name, typeId.text(in: context))
            }
            // Inferred `var h = Helper()` / `var h = compute()`: a `value` identifier followed by a
            // `selector` argument part.
            guard let value = node.child(byFieldName: "value"), value.nodeType == "identifier",
                  node.namedChildren().contains(where: {
                      $0.nodeType == "selector" && $0.firstChild(withType: "argument_part") != nil
                  })
            else { return nil }
            let valueText = value.text(in: context)
            if declaredTypeNames.contains(valueText) {
                return (name, valueText)
            }
            if let returnType = scope.knownMethodReturnTypes[valueText] {
                return (name, returnType)
            }
            return nil
        }
    }
}
