import AcaiCore
import AcaiTreeSitter

struct KotlinCallSiteSyntax: CallSiteSyntax {

    let context: SourceFileContext

    /// From the pre-pass: constructing one of these is what makes a local's type provable.
    let declaredTypeNames: Set<String>

    /// Resolves statically-determinable Kotlin call patterns:
    /// - `receiver.method(args)` / `this.receiver.method(args)` where `receiver` is a known property,
    /// - `this.method(args)` — a call on the enclosing instance,
    /// - `TypeName.method(args)` where `TypeName` is a known (companion/static) type.
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

        // Method name lives in the last navigation_suffix → simple_identifier
        guard let navSuffix = navExpr.firstChild(withType: "navigation_suffix"),
              let methodNode = navSuffix.firstChild(withType: "simple_identifier")
        else { return nil }
        let methodName = methodNode.text(in: context)

        // Pattern: this.method(args) — a direct call on the enclosing instance.
        if navExpr.firstChild(withType: "this_expression") != nil {
            return CallSite(receiver: .selfDispatch, methodName: methodName, location: node.location(in: context))
        }

        var receiverName: String?
        if let firstId = navExpr.firstChild(withType: "simple_identifier") {
            // Pattern: receiver.method(args)
            receiverName = firstId.text(in: context)
        } else if let innerNav = navExpr.firstChild(withType: "navigation_expression"),
                  innerNav.firstChild(withType: "this_expression") != nil,
                  let innerSuffix = innerNav.firstChild(withType: "navigation_suffix"),
                  let propId = innerSuffix.firstChild(withType: "simple_identifier") {
            // Pattern: this.receiver.method(args)
            receiverName = propId.text(in: context)
        }

        guard let name = receiverName else { return nil }
        return scope.resolvedCallSite(receiverName: name, methodName: methodName, location: node.location(in: context))
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
