import UMLCore
import UMLTreeSitter

// MARK: - Call-site resolution

extension CFamilyExtractor: CallSiteResolving {

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
            return fieldExpressionCallSite(function, scope: scope, location: loc(node))
        case "qualified_identifier":
            return qualifiedCallSite(function, scope: scope, location: loc(node))
        case "identifier":
            // Bare `foo(args)` — a C free function, or (C++) an implicit `this->foo()` sibling-method
            // call. Tagged `.selfDispatch`: the call-graph builder resolves it against the enclosing
            // type first, then falls back to a free function (a freestanding C caller has an empty
            // caller type, so it resolves straight through the free fallback). The `declaredFunctionNames`
            // guard keeps stdlib calls (`printf`, …) out of the coverage denominator.
            let name = text(function)
            guard declaredFunctionNames.contains(name) else { return nil }
            return CallSite(receiver: .selfDispatch, methodName: name, location: loc(node))
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
        let methodName = text(field)

        // `this->method()` / `this.method()` — a call on the enclosing instance.
        if receiver.nodeType == "this" {
            return CallSite(receiver: .selfDispatch, methodName: methodName, location: location)
        }
        // Only a simple, provably-typed receiver is resolved.
        guard receiver.nodeType == "identifier" else { return nil }
        return scope.resolvedCallSite(
            receiverName: text(receiver), methodName: methodName, location: location
        )
    }

    private func qualifiedCallSite(
        _ node: Node, scope: CallSiteScope, location: SourceLocation
    ) -> CallSite? {
        guard let scopeNode = node.child(byFieldName: "scope"),
              let nameNode = node.child(byFieldName: "name")
        else { return nil }
        return scope.resolvedCallSite(
            receiverName: Self.lastComponent(of: text(scopeNode)),
            methodName: text(nameNode),
            location: location
        )
    }

    /// Provable local-variable types: an explicit declared type (`Foo x;` / `Foo* p = …;`) or an
    /// `auto p = new Foo()` construction, so `x.method()` / `p->method()` resolves to `Foo` (RC4).
    func localBindings(in body: Node) -> [String: String] {
        collectLocalBindings(in: body) { node in
            guard node.nodeType == "declaration",
                  let declarator = node.child(byFieldName: "declarator"),
                  let name = declaratorIdentifier(declarator)
            else { return nil }
            if let typeNode = node.child(byFieldName: "type"), typeNode.nodeType == "type_identifier" {
                return (name, text(typeNode))
            }
            if declarator.nodeType == "init_declarator",
               let value = declarator.child(byFieldName: "value"), value.nodeType == "new_expression",
               let typeNode = value.child(byFieldName: "type"), typeNode.nodeType == "type_identifier" {
                return (name, text(typeNode))
            }
            return nil
        }
    }

    /// Digs through `init_declarator`/`pointer_declarator`/`reference_declarator` wrappers to the
    /// declared variable's identifier.
    private func declaratorIdentifier(_ node: Node) -> String? {
        switch node.nodeType {
        case "identifier", "field_identifier":
            return text(node)
        case "init_declarator", "pointer_declarator", "reference_declarator", "array_declarator":
            if let inner = node.child(byFieldName: "declarator") { return declaratorIdentifier(inner) }
            return node.firstChild(withType: "identifier").map { text($0) }
        default:
            return node.firstChild(withType: "identifier").map { text($0) }
        }
    }
}
