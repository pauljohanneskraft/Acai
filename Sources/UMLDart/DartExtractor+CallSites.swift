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
        // A field or constructor-init initializer `field = callee(args)` flattens as siblings
        // [field-id, callee-id, selector(argument_part)] inside `field_initializer` (constructor init
        // list) or `initialized_identifier` (field declaration). Capture the callee as a bare call; the
        // guard drops constructions `Foo()` and initializers that aren't a call (RC2).
        if node.nodeType == "field_initializer" || node.nodeType == "initialized_identifier" {
            let kids = node.namedChildren()
            guard kids.count >= 2,
                  kids[kids.count - 1].nodeType == "selector",
                  kids[kids.count - 1].firstChild(withType: "argument_part") != nil,
                  kids[kids.count - 2].nodeType == "identifier"
            else { return nil }
            return scope.bareCall(named: text(kids[kids.count - 2]), implicitSelf: true, location: loc(node))
        }

        let named = node.namedChildren()

        // Bare `foo(args)` — an `identifier` callee and a single `selector` carrying the `argument_part`
        // (no separate receiver node). An implicit `this.foo()` or a top-level function; tagged
        // `.selfDispatch` so the call-graph builder can fall back to a free function. The `knownTypeNames`
        // guard in `bareCall` drops constructor calls `Foo()`, which share this shape.
        if named.count == 2,
           named[0].nodeType == "identifier",
           named[1].nodeType == "selector",
           named[1].firstChild(withType: "argument_part") != nil {
            return scope.bareCall(named: text(named[0]), implicitSelf: true, location: loc(node))
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

        let methodName = text(methodId)

        // Pattern: this.method(args) — a direct call on the enclosing instance.
        if receiverNode.nodeType == "this" {
            return CallSite(receiver: .selfDispatch, methodName: methodName, location: loc(node))
        }

        guard receiverNode.nodeType == "identifier" else { return nil }
        return scope.resolvedCallSite(
            receiverName: text(receiverNode),
            methodName: methodName,
            location: loc(node)
        )
    }

    /// Appends a constructor initializer-list's call sites (`: x = compute()`) to the just-appended
    /// member, with that member's own parameters available as receivers (RC2 + RC-G).
    func appendInitializerListCallSites(_ initializers: Node, to members: inout [Member]) {
        let lastIndex = members.count - 1
        members[lastIndex].callSites += extractCallSites(
            from: initializers,
            scope: CallSiteScope(knownTypeNames: declaredTypeNames)
                .merging(parameters: members[lastIndex].parameters))
    }

    /// Resolves and attaches call sites for the recorded method bodies, using a scope built
    /// from the type's fully-extracted members (so all stored properties are known) plus the
    /// current file's known type names.
    func attachCallSites(_ pendingBodies: [(index: Int, body: Node)], to members: inout [Member]) {
        guard !pendingBodies.isEmpty else { return }
        let scope = CallSiteScope(
            knownProperties: buildPropertyMap(from: members),
            knownTypeNames: declaredTypeNames,
            knownMethodReturnTypes: methodReturnTypeMap(from: members)
        )
        for pending in pendingBodies where pending.index < members.count {
            // `+=`: a constructor may already carry initializer-list call sites set during the body walk.
            members[pending.index].callSites += extractCallSites(
                from: pending.body, scope: scope.merging(parameters: members[pending.index].parameters))
            members[pending.index].fieldReads = fieldReadResolver.reads(in: pending.body, scope: scope)
            members[pending.index].referencedTypeNames = referencedTypeNames(in: pending.body)
            members[pending.index].cyclomaticComplexity =
                cyclomaticComplexity(in: pending.body, branchKinds: Self.branchNodeKinds)
        }
    }

    /// A Dart method with no paired body is abstract (a body-less method is only legal as an abstract
    /// requirement); mark it so the dead-code scan treats it as a reachable-by-contract member — the
    /// analogue of an interface requirement, which Dart expresses with abstract classes (RC3).
    func markBodylessMethodsAbstract(_ members: inout [Member], bodiedIndices: Set<Int>) {
        for index in members.indices
        where members[index].kind == .method
            && !bodiedIndices.contains(index)
            && !members[index].modifiers.contains(.abstract) {
            members[index].modifiers.append(.abstract)
        }
    }

    /// Provable local-variable types: an explicit annotation (`Helper h = …`), an inferred
    /// construction (`var h = Helper()`) of a declared type, or a same-type method call with an
    /// unambiguous return type (`var h = compute()`, via `scope.knownMethodReturnTypes`), so
    /// `h.method()` resolves to `Helper` (RC4/RC-I).
    func localBindings(in body: Node, scope: CallSiteScope) -> [String: String] {
        collectLocalBindings(in: body) { node in
            guard node.nodeType == "initialized_variable_definition",
                  let nameNode = node.child(byFieldName: "name")
            else { return nil }
            let name = text(nameNode)
            if let typeId = node.firstChild(withType: "type_identifier") {
                return (name, text(typeId))
            }
            // Inferred `var h = Helper()` / `var h = compute()`: a `value` identifier followed by a
            // `selector` argument part.
            guard let value = node.child(byFieldName: "value"), value.nodeType == "identifier",
                  node.namedChildren().contains(where: {
                      $0.nodeType == "selector" && $0.firstChild(withType: "argument_part") != nil
                  })
            else { return nil }
            if declaredTypeNames.contains(text(value)) {
                return (name, text(value))
            }
            if let returnType = scope.knownMethodReturnTypes[text(value)] {
                return (name, returnType)
            }
            return nil
        }
    }
}
