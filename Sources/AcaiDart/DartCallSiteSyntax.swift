import AcaiCore
import AcaiTreeSitter

struct DartCallSiteSyntax: CallSiteSyntax {

    let context: SourceFileContext

    /// From the pre-pass: constructing one of these is what makes a local's type provable.
    let declaredTypeNames: Set<String>

    /// Resolves statically-determinable Dart call patterns: `receiver.method(args)` where
    /// `receiver` is a known property, `this.method(args)`, `TypeName.method(args)` (static call),
    /// and one-hop chains — `this.prop.method(args)` and `head.hop.method(args)`, the latter a
    /// deferred `.propertyChain` where the head resolves.
    ///
    /// The Dart grammar flattens a call into siblings — the receiver, one `selector` per `.` hop,
    /// then a trailing `selector` carrying `argument_part` — rather than nesting it, so the receiver
    /// is reassembled here before the shared decision tree sees it. A chain deeper than one hop has
    /// more selectors still and is dropped, as it is in every other language.
    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        // `field = callee(args)` flattens as siblings [field-id, callee-id, selector(argument_part)]
        // inside `field_initializer` or `initialized_identifier`. The guard drops constructions
        // `Foo()` and non-call initializers.
        if node.nodeType == "field_initializer" || node.nodeType == "initialized_identifier" {
            let kids = node.namedChildren()
            guard kids.count >= 2,
                  isArgumentSelector(kids[kids.count - 1]),
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
           isArgumentSelector(named[1]) {
            return scope.bareCall(
                named: named[0].text(in: context), implicitSelf: true, location: node.location(in: context)
            )
        }

        guard named.count == 3 || named.count == 4,
              isArgumentSelector(named[named.count - 1]),
              let methodName = selectorName(named[named.count - 2])
        else { return nil }

        let resolver = MemberCallResolver(syntax: DartMemberReceiverSyntax(context: context))
        let location = node.location(in: context)
        guard named.count == 4 else {
            return resolver.callSite(
                receiver: named[0], methodName: methodName, scope: scope, location: location
            )
        }
        guard let hop = selectorName(named[1]) else { return nil }
        return resolver.callSite(
            receiver: .memberAccess(object: named[0], hop: hop),
            methodName: methodName, scope: scope, location: location
        )
    }

    /// The trailing `selector` that carries the call's arguments — what makes the shape a call at
    /// all rather than a plain property access.
    private func isArgumentSelector(_ node: Node) -> Bool {
        node.nodeType == "selector" && node.firstChild(withType: "argument_part") != nil
    }

    /// The name a `.foo` hop selector carries.
    private func selectorName(_ node: Node) -> String? {
        guard node.nodeType == "selector",
              let assignable = node.firstChild(withType: "unconditional_assignable_selector"),
              let identifier = assignable.firstChild(withType: "identifier")
        else { return nil }
        return identifier.text(in: context)
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

/// Dart flattens a member access into sibling selectors rather than nesting it, so only the head of
/// a chain is ever a node to decompose — `DartCallSiteSyntax` assembles the `.memberAccess` case
/// itself.
struct DartMemberReceiverSyntax: MemberReceiverSyntax {

    let context: SourceFileContext

    func receiver(_ node: Node) -> MemberReceiver? {
        switch node.nodeType {
        case "this":
            return .selfExpression
        case "identifier":
            return .name(node.text(in: context))
        default:
            return nil
        }
    }
}
