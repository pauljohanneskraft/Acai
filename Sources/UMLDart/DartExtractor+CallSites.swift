import UMLCore
import UMLTreeSitter

// MARK: - Call Site Resolution

extension DartExtractor: CallSiteResolving {

    /// Resolves statically-determinable Dart call patterns.
    ///
    /// The Dart grammar flattens a call like `receiver.method(args)` into a sequence of
    /// siblings: `receiver` (an `identifier` or `this`), a `selector` carrying the method
    /// name (`unconditional_assignable_selector → identifier`), and a trailing `selector`
    /// carrying the `argument_part`. Only the simple three-part shape is matched — chains
    /// such as `a.b.c()` have an extra selector and are skipped, keeping resolution certain.
    ///
    /// Handles:
    /// - `receiver.method(args)` where `receiver` is a known property,
    /// - `this.method(args)` — a call on the enclosing instance,
    /// - `TypeName.method(args)` where `TypeName` is a known type (static call).
    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        let named = node.namedChildren()
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

        let methodName = text(methodId)

        // Pattern: this.method(args) — a direct call on the enclosing instance.
        if receiverNode.nodeType == "this" {
            return CallSite(receiverType: nil, methodName: methodName, location: loc(node))
        }

        guard receiverNode.nodeType == "identifier" else { return nil }
        return scope.resolvedCallSite(
            receiverName: text(receiverNode),
            methodName: methodName,
            location: loc(node)
        )
    }
}
