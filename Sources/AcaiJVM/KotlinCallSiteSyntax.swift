import AcaiCore
import AcaiTreeSitter

struct KotlinCallSiteSyntax: CallSiteSyntax {

    let context: SourceFileContext

    /// From the pre-pass: constructing one of these is what makes a local's type provable.
    let declaredTypeNames: Set<String>

    /// Resolves statically-determinable Kotlin call patterns:
    /// - `receiver.method(args)` / `this.receiver.method(args)` where `receiver` is a known property,
    /// - `this.method(args)` — a call on the enclosing instance,
    /// - `TypeName.method(args)` where `TypeName` is a known (companion/static) type,
    /// - `head.hop.method(args)` whose head resolves but whose hop doesn't — a deferred
    ///   `.propertyChain` the post-merge pass finishes.
    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        guard node.nodeType == "call_expression" else { return nil }

        guard let navExpr = node.firstChild(withType: "navigation_expression") else {
            // Bare `foo()` — an implicit-receiver call (a member of the enclosing type or a top-level
            // function). Tagged `.selfDispatch`; the builder falls back to a free function. The
            // `knownTypeNames` guard drops constructor calls `Foo()`, which share this grammar shape.
            guard let calleeId = node.firstChild(withType: "simple_identifier") else { return nil }
            return scope.bareCall(
                named: calleeId.text(in: context), implicitSelf: true, location: node.location(in: context)
            )
        }

        // The grammar nests each `.` as another `navigation_expression`, so the method name is this
        // level's suffix and everything before it is the receiver.
        guard let navSuffix = navExpr.firstChild(withType: "navigation_suffix"),
              let methodNode = navSuffix.firstChild(withType: "simple_identifier"),
              let receiver = navExpr.namedChildren().first
        else { return nil }

        return MemberCallResolver(syntax: KotlinMemberReceiverSyntax(context: context)).callSite(
            receiver: receiver,
            methodName: methodNode.text(in: context),
            scope: scope,
            location: node.location(in: context)
        )
    }

    /// Provable local-variable types: an explicit annotation (`val x: Foo`), a `Foo()` construction of
    /// a declared type (`val x = Foo()`), or a same-type method call with an unambiguous return type
    /// (`val x = compute()`, via `scope.knownMethodReturnTypes`), so `x.method()` resolves to `Foo`.
    func localBindings(in body: Node, scope: CallSiteScope) -> [String: String] {
        collectLocalBindings(in: body) { node in
            guard node.nodeType == "property_declaration",
                  let varDecl = node.firstChild(withType: "variable_declaration"),
                  let nameNode = varDecl.firstChild(withType: "simple_identifier")
            else { return nil }
            let name = nameNode.text(in: context)
            if let userType = varDecl.firstChild(withType: "user_type"),
               let typeId = userType.firstChild(withType: "type_identifier") {
                return (name, typeId.text(in: context))
            }
            guard let call = node.firstChild(withType: "call_expression"),
                  call.firstChild(withType: "navigation_expression") == nil,
                  let callee = call.firstChild(withType: "simple_identifier")
            else { return nil }
            let calleeText = callee.text(in: context)
            if declaredTypeNames.contains(calleeText) {
                return (name, calleeText)
            }
            if let returnType = scope.knownMethodReturnTypes[calleeText] {
                return (name, returnType)
            }
            return nil
        }
    }
}

/// Kotlin spells a member access as a nested `navigation_expression`, not as `object`/`field`
/// fields, so it decomposes a receiver itself rather than through `MemberCallGrammar`.
struct KotlinMemberReceiverSyntax: MemberReceiverSyntax {

    let context: SourceFileContext

    func receiver(_ node: Node) -> MemberReceiver? {
        switch node.nodeType {
        case "this_expression":
            return .selfExpression
        case "simple_identifier":
            return .name(node.text(in: context))
        case "navigation_expression":
            guard let object = node.namedChildren().first,
                  let suffix = node.firstChild(withType: "navigation_suffix"),
                  let hop = suffix.firstChild(withType: "simple_identifier")
            else { return nil }
            return .memberAccess(object: object, hop: hop.text(in: context))
        default:
            return nil
        }
    }
}
