import AcaiCore
import AcaiTreeSitter

struct CFamilyCallSiteSyntax: CallSiteSyntax {

    let context: SourceFileContext
    let typeReferences: CFamilyTypeReferenceResolver

    /// Simple names of every function/method declared in the file, from the pre-pass, so an
    /// unqualified call `foo()` can be resolved to a free function / same-type method (and only
    /// then) — keeps stdlib calls (`printf`, …) out of the coverage denominator.
    let declaredFunctionNames: Set<String>

    /// Resolves statically-determinable C/C++ call patterns from a `call_expression`:
    /// - `receiver.method(args)` / `receiver->method(args)` where `receiver` is a known property,
    /// - `this->method(args)` — a call on the enclosing instance,
    /// - `Type::method(args)` where `Type` is a known type (static call),
    /// - `function(args)` where `function` is a declared free function / same-type method.
    /// Anything else (chained accesses, calls on unknown receivers) is dropped to keep resolution
    /// certain and the diagrams free of phantom participants.
    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        guard node.nodeType == "call_expression",
              let function = node.child(byFieldName: "function")
        else { return nil }

        switch function.nodeType {
        case "field_expression":
            return fieldExpressionCallSite(function, scope: scope, location: node.location(in: context))
        case "qualified_identifier":
            return qualifiedCallSite(function, scope: scope, location: node.location(in: context))
        case "identifier":
            // Bare `foo(args)` — a C free function, or (C++) an implicit `this->foo()` sibling call.
            // Tagged `.selfDispatch`: the call-graph builder tries the enclosing type first, then
            // falls back to a free function.
            let name = function.text(in: context)
            guard declaredFunctionNames.contains(name) else { return nil }
            return CallSite(receiver: .selfDispatch, methodName: name, location: node.location(in: context))
        default:
            return nil
        }
    }

    private func fieldExpressionCallSite(
        _ node: Node, scope: CallSiteScope, location: SourceLocation
    ) -> CallSite? {
        guard let field = node.child(byFieldName: "field"),
              let receiver = node.child(byFieldName: "argument")
        else { return nil }
        let methodName = field.text(in: context)

        if receiver.nodeType == "this" {
            return CallSite(receiver: .selfDispatch, methodName: methodName, location: location)
        }
        guard receiver.nodeType == "identifier" else { return nil }
        return scope.resolvedCallSite(
            receiverName: receiver.text(in: context), methodName: methodName, location: location
        )
    }

    private func qualifiedCallSite(
        _ node: Node, scope: CallSiteScope, location: SourceLocation
    ) -> CallSite? {
        guard let scopeNode = node.child(byFieldName: "scope"),
              let nameNode = node.child(byFieldName: "name")
        else { return nil }
        return scope.resolvedCallSite(
            receiverName: typeReferences.lastComponent(of: scopeNode.text(in: context)),
            methodName: nameNode.text(in: context),
            location: location
        )
    }

    /// Provable local-variable types: an explicit declared type (`Foo x;` / `Foo* p = …;`), an
    /// `auto p = new Foo()` construction, or a same-type method call with an unambiguous return type
    /// (`auto x = compute();`, via `scope.knownMethodReturnTypes`), so `x.method()` / `p->method()`
    /// resolves to `Foo`.
    func localBindings(in body: Node, scope: CallSiteScope) -> [String: String] {
        collectLocalBindings(in: body) { node in
            guard node.nodeType == "declaration",
                  let declarator = node.child(byFieldName: "declarator"),
                  let name = declaratorIdentifier(declarator)
            else { return nil }
            if let typeNode = node.child(byFieldName: "type"), typeNode.nodeType == "type_identifier" {
                return (name, typeNode.text(in: context))
            }
            guard declarator.nodeType == "init_declarator",
                  let value = declarator.child(byFieldName: "value")
            else { return nil }
            if value.nodeType == "new_expression",
               let typeNode = value.child(byFieldName: "type"), typeNode.nodeType == "type_identifier" {
                return (name, typeNode.text(in: context))
            }
            if value.nodeType == "call_expression",
               let function = value.child(byFieldName: "function"), function.nodeType == "identifier",
               let returnType = scope.knownMethodReturnTypes[function.text(in: context)] {
                return (name, returnType)
            }
            return nil
        }
    }

    /// Digs through `init_declarator`/`pointer_declarator`/`reference_declarator` wrappers to the
    /// declared variable's identifier.
    private func declaratorIdentifier(_ node: Node) -> String? {
        switch node.nodeType {
        case "identifier", "field_identifier":
            return node.text(in: context)
        case "init_declarator", "pointer_declarator", "reference_declarator", "array_declarator":
            if let inner = node.child(byFieldName: "declarator") { return declaratorIdentifier(inner) }
            return node.firstChild(withType: "identifier").map { $0.text(in: context) }
        default:
            return node.firstChild(withType: "identifier").map { $0.text(in: context) }
        }
    }
}
