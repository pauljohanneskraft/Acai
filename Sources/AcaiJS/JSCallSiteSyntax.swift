import AcaiCore
import AcaiTreeSitter

struct JSCallSiteSyntax: CallSiteSyntax {

    let context: SourceFileContext

    private static let memberCallGrammar = MemberCallGrammar(
        selfNodeType: "this", memberAccessType: "member_expression", memberField: "property"
    )

    /// Matches JS/TS `call_expression { function: member_expression { object, property } }`:
    /// `receiver.method(args)` (object is a known property/type), `this.receiver.method(args)`,
    /// `this.method(args)`, `TypeName.method(args)`.
    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        guard node.nodeType == "call_expression",
              let funcNode = node.child(byFieldName: "function")
        else { return nil }

        // Bare `foo()` — no receiver. JS has no implicit `this`, so this is a free/imported function.
        if funcNode.nodeType == "identifier" {
            return scope.bareCall(
                named: funcNode.text(in: context), implicitSelf: false, location: node.location(in: context))
        }

        guard funcNode.nodeType == "member_expression",
              let propertyNode = funcNode.child(byFieldName: "property"),
              let objectNode   = funcNode.child(byFieldName: "object")
        else { return nil }

        return MemberCallResolver(context: context, grammar: Self.memberCallGrammar).callSite(
            receiver: objectNode,
            methodName: propertyNode.text(in: context),
            scope: scope,
            location: node.location(in: context)
        )
    }

    /// Provable local-variable types: a TypeScript annotation (`const x: Foo`), a `new Foo()`
    /// construction, or a same-type method call with an unambiguous return type (`const x =
    /// compute()`, via `scope.knownMethodReturnTypes`), so `x.method()` resolves to `Foo`.
    func localBindings(in body: Node, scope: CallSiteScope) -> [String: String] {
        collectLocalBindings(in: body) { node in
            guard node.nodeType == "variable_declarator",
                  let nameNode = node.child(byFieldName: "name"), nameNode.nodeType == "identifier"
            else { return nil }
            let name = nameNode.text(in: context)
            if let typeAnnotation = node.child(byFieldName: "type"),
               let typeId = typeAnnotation.firstChild(withType: "type_identifier") {
                return (name, typeId.text(in: context))
            }
            guard let value = node.child(byFieldName: "value") else { return nil }
            if value.nodeType == "new_expression",
               let ctor = value.child(byFieldName: "constructor"), ctor.nodeType == "identifier" {
                return (name, ctor.text(in: context))
            }
            if value.nodeType == "call_expression",
               let callee = value.child(byFieldName: "function"), callee.nodeType == "identifier",
               let returnType = scope.knownMethodReturnTypes[callee.text(in: context)] {
                return (name, returnType)
            }
            return nil
        }
    }
}
