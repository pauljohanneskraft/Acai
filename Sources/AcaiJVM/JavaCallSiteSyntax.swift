import AcaiCore
import AcaiTreeSitter

struct JavaCallSiteSyntax: CallSiteSyntax {

    let context: SourceFileContext

    private static let memberCallGrammar = MemberCallGrammar(
        selfNodeType: "this", memberAccessType: "field_access", memberField: "field"
    )

    /// Matches Java `method_invocation` nodes: `receiver.method(args)` (object is a known property or
    /// type), `this.receiver.method(args)`, `this.method(args)`, `TypeName.method(args)`.
    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        guard node.nodeType == "method_invocation",
              let nameNode = node.child(byFieldName: "name")
        else { return nil }

        // Bare `foo()` — no `object` field: an implicit `this.foo()` (or a static import). Tag it
        // `.selfDispatch`; the call-graph builder falls back to a free function if it is a static import.
        guard let objectNode = node.child(byFieldName: "object") else {
            return scope.bareCall(
                named: nameNode.text(in: context), implicitSelf: true, location: node.location(in: context))
        }

        return MemberCallResolver(context: context, grammar: Self.memberCallGrammar).callSite(
            receiver: objectNode,
            methodName: nameNode.text(in: context),
            scope: scope,
            location: node.location(in: context)
        )
    }

    /// Provable local-variable types: an explicit annotation (`Foo x = …`), a `new Foo()` construction
    /// (`var x = new Foo()`), or a same-type method call with an unambiguous return type (`var x =
    /// compute()`, via `scope.knownMethodReturnTypes`), so `x.method()` resolves to `Foo`.
    func localBindings(in body: Node, scope: CallSiteScope) -> [String: String] {
        collectLocalBindings(in: body) { node in
            guard node.nodeType == "local_variable_declaration",
                  let declarator = node.child(byFieldName: "declarator"),
                  let nameNode = declarator.child(byFieldName: "name")
            else { return nil }
            let name = nameNode.text(in: context)
            if let typeNode = node.child(byFieldName: "type"),
               typeNode.nodeType == "type_identifier", typeNode.text(in: context) != "var" {
                return (name, typeNode.text(in: context))
            }
            guard let value = declarator.child(byFieldName: "value") else { return nil }
            if value.nodeType == "object_creation_expression",
               let typeNode = value.child(byFieldName: "type") {
                return (name, typeNode.text(in: context))
            }
            if value.nodeType == "method_invocation", value.child(byFieldName: "object") == nil,
               let methodName = value.child(byFieldName: "name").map({ $0.text(in: context) }),
               let returnType = scope.knownMethodReturnTypes[methodName] {
                return (name, returnType)
            }
            return nil
        }
    }
}
