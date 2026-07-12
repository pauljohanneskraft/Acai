import SwiftSyntax
import UMLCore

/// Resolves the body-level facts the sequence/state generators need — call sites, assignments, and
/// referenced type names — from individual expression nodes. Holds no traversal state: the visitor
/// drives the walk and hands each node (plus the current property map) here for interpretation, so
/// all the expression-shape knowledge lives in one place instead of inside the visitor.
struct CallSiteCollector {
    /// Simple names of every type declared in the file, used to recognise `TypeName.method()`
    /// static calls.
    let knownTypeNames: Set<String>

    private let sourceLocations = SourceLocationResolver()
    private let values = SwiftValueClassifier()

    /// A resolvable call site (`receiver.method()`), or `nil` when the receiver can't be resolved to
    /// a known property/type and the call should be dropped. `propertyMap` is the current type's
    /// `storedPropertyName → declaredTypeName` map.
    func callSite(
        from node: FunctionCallExprSyntax, propertyMap: [String: String],
        enclosingTypeName: String?, fileName: String
    ) -> CallSite? {
        let callee = unwrappedCallee(node.calledExpression)
        if let memberAccess = callee.as(MemberAccessExprSyntax.self) {
            let methodName = memberAccess.declName.baseName.text
            guard let resolved = resolveReceiver(
                from: memberAccess.base, propertyMap: propertyMap,
                enclosingTypeName: enclosingTypeName) else { return nil }
            return CallSite(
                receiver: resolved.receiver,
                methodName: methodName,
                location: sourceLocations.sourceLocation(of: node, fileName: fileName)
            )
        }
        if let declRef = callee.as(DeclReferenceExprSyntax.self) {
            return implicitCall(named: declRef.baseName.text, node: node, propertyMap: propertyMap, fileName: fileName)
        }
        return nil
    }

    /// A bare `foo()` — an implicit-`self` method call or a free-function call. We can't tell which at
    /// parse time (a free function may live in another file), so we record `.selfDispatch` and let the
    /// whole-artifact resolvers (`CallGraphBuilder`, `SequenceDiagramBuilder`) match it against the
    /// caller's own methods first, then free functions. A construction (`Foo()`) or a call through a
    /// stored closure property (`handler()`) isn't a resolvable call target, so it's dropped.
    private func implicitCall(
        named name: String, node: FunctionCallExprSyntax, propertyMap: [String: String], fileName: String
    ) -> CallSite? {
        guard !isTypeName(name), propertyMap[name] == nil else { return nil }
        return CallSite(
            receiver: .selfDispatch,
            methodName: name,
            location: sourceLocations.sourceLocation(of: node, fileName: fileName)
        )
    }

    /// Treats a same-file declared type or any capitalised identifier as a type name, so `Foo()` /
    /// `UUID()` / `URL()` read as construction, not a call. Cross-file types aren't in `knownTypeNames`,
    /// hence the capitalisation guard; Swift methods are lowerCamelCase by convention.
    private func isTypeName(_ name: String) -> Bool {
        knownTypeNames.contains(name) || name.first?.isUppercase == true
    }

    /// Strips `foo<T>()` generic-specialisation and `foo?()` optional-chaining wrappers so the callee
    /// reduces to its underlying `MemberAccessExprSyntax` / `DeclReferenceExprSyntax`.
    private func unwrappedCallee(_ expr: ExprSyntax) -> ExprSyntax {
        if let generic = expr.as(GenericSpecializationExprSyntax.self) { return generic.expression }
        if let optional = expr.as(OptionalChainingExprSyntax.self) { return optional.expression }
        return expr
    }

    /// A variable assignment recovered from a `SequenceExprSyntax`, or `nil` if the sequence is not an
    /// assignment.
    ///
    /// The file is parsed without operator folding, so `x = expr` surfaces as a `SequenceExprSyntax`
    /// whose elements are `[target, AssignmentExpr, value…]`, and compound assignments as
    /// `[target, BinaryOperatorExpr(+=), value…]`.
    func assignment(from node: SequenceExprSyntax, fileName: String) -> VariableAssignment? {
        let elements = Array(node.elements)
        guard elements.count >= 3, let target = values.target(of: elements[0]) else { return nil }

        let op: VariableAssignment.Operator
        if elements[1].is(AssignmentExprSyntax.self) {
            op = .assign
        } else if let binaryOperator = elements[1].as(BinaryOperatorExprSyntax.self),
                  values.compoundAssignmentOperators.contains(binaryOperator.operator.text) {
            op = .compound
        } else {
            return nil
        }

        // Compound results depend on the previous value, so record the whole statement as a
        // non-enumerable expression. For plain assignments, exactly one RHS element is classifiable;
        // longer tails (`a = b ? x : y` folds the ternary into one element, but `a = b = c` does not)
        // are treated as non-enumerable expressions.
        let value: VariableAssignment.Value
        if op == .compound {
            let joined = node.trimmedDescription.replacingOccurrences(of: "\n", with: " ")
            value = .init(kind: .expression, text: String(joined.prefix(80)))
        } else if elements.count == 3 {
            value = values.classify(elements[2])
        } else {
            let joined = elements[2...].map(\.trimmedDescription).joined(separator: " ")
            value = .init(kind: .expression, text: String(joined.prefix(80)))
        }

        return VariableAssignment(
            targetName: target.name,
            targetReceiver: target.receiver,
            op: op,
            value: value,
            location: sourceLocations.sourceLocation(of: node, fileName: fileName)
        )
    }

    /// A read of a stored property, or `nil` when the identifier is not one of the type's properties.
    /// `propertyMap` is the current type's `storedPropertyName → declaredTypeName` map. Bare
    /// identifiers and the member of a `self.x` access both surface as `DeclReferenceExprSyntax`, so
    /// this records them with `receiver == nil`; consumers filter by name (issue #111).
    func fieldRead(
        from node: DeclReferenceExprSyntax, propertyMap: [String: String], fileName: String
    ) -> FieldAccess? {
        let name = node.baseName.text
        guard propertyMap[name] != nil else { return nil }
        return FieldAccess(
            name: name,
            receiver: nil,
            location: sourceLocations.sourceLocation(of: node, fileName: fileName)
        )
    }

    /// The capitalised type-like names referenced inside a syntax subtree (constructions, static
    /// access, casts, annotations) — the construction/body dependencies fed to the coupling metrics.
    func referencedTypes(in node: some SyntaxProtocol) -> [String] {
        let collector = TypeReferenceCollector()
        collector.walk(node)
        return Array(collector.names)
    }

    // MARK: - Receiver resolution

    /// A statically-resolved call-site receiver. `.selfDispatch` denotes a call on the enclosing
    /// instance (`self.method()`), which the sequence-diagram generator renders as a self-message
    /// keyed on the caller's type.
    private struct ResolvedReceiver {
        let receiver: CallReceiver
    }

    /// Resolves the declared type for a receiver expression.
    ///
    /// Handles (only when provably resolvable, or deferrable to the post-merge pass — otherwise
    /// returns `nil`, dropping the call):
    /// - `varName.method()` — known stored property → its declared type (`.type`),
    /// - `self.varName.method()` — strips the leading `self.` then looks up the property (`.type`),
    /// - `self.method()` — a call on the enclosing instance (`.selfDispatch`),
    /// - `Self.method()` — a static call on the enclosing type (`.type(enclosingTypeName)`), kept
    ///   distinct from `self.method()`/bare `method()`: Swift itself disambiguates static (`Self.`)
    ///   from instance (`self.`/implicit) dispatch, so collapsing both into `.selfDispatch` would
    ///   make a same-named static/instance pair on one type unresolvable to "which one,"
    /// - `TypeName.method()` — `TypeName` is a known type → a static call (`.type`),
    /// - a capitalised receiver not known in this file — `TypeName.method()` where `TypeName` is
    ///   declared *elsewhere* in the project → deferred (`.unresolvedTypeName`), resolved post-merge
    ///   by `CodeArtifact.resolvingCallSiteReceivers()` (RC-cross-file),
    /// - `a.b.method()` where `a` (or `self.a`) resolves to a known type but `b` isn't a property of
    ///   *this* file's types → deferred (`.propertyChain`), resolved post-merge by walking `b`'s
    ///   declared type on `a`'s type through the full project type graph (RC-multi-hop).
    private func resolveReceiver(
        from base: ExprSyntax?, propertyMap: [String: String], enclosingTypeName: String?
    ) -> ResolvedReceiver? {
        guard let base else { return nil }

        if let declRef = base.as(DeclReferenceExprSyntax.self) {
            return resolveIdentifierReceiver(
                declRef, propertyMap: propertyMap, enclosingTypeName: enclosingTypeName)
        }

        if let memberAccess = base.as(MemberAccessExprSyntax.self) {
            return resolveChainedReceiver(
                memberAccess, propertyMap: propertyMap, enclosingTypeName: enclosingTypeName)
        }

        // `Foo(...).method()` — a call on a freshly constructed value resolves to `Foo`.
        if let call = base.as(FunctionCallExprSyntax.self), let type = constructedTypeName(call) {
            return ResolvedReceiver(receiver: .type(type))
        }

        return nil
    }

    /// Resolves a bare-identifier receiver (`self`, `Self`, a known property, a same-file type name,
    /// or a capitalised name deferred to the post-merge cross-file pass).
    private func resolveIdentifierReceiver(
        _ declRef: DeclReferenceExprSyntax, propertyMap: [String: String], enclosingTypeName: String?
    ) -> ResolvedReceiver? {
        let name = declRef.baseName.text
        if name == "self" {
            return ResolvedReceiver(receiver: .selfDispatch)
        }
        if name == "Self" {
            guard let enclosingTypeName else { return nil }
            return ResolvedReceiver(receiver: .type(enclosingTypeName))
        }
        if let propertyType = propertyMap[name] {
            return ResolvedReceiver(receiver: .type(propertyType))
        }
        if knownTypeNames.contains(name) {
            return ResolvedReceiver(receiver: .type(name))
        }
        // Capitalised but not a type declared in *this* file: possibly declared elsewhere in the
        // project. Deferred rather than dropped — resolved post-merge when the full type set is
        // known, and left as this case (never guessed) if no unambiguous match turns up.
        if name.first?.isUppercase == true {
            return ResolvedReceiver(receiver: .unresolvedTypeName(name))
        }
        return nil
    }

    /// Resolves a member-access receiver (`self.prop.method()`, or a deeper chain deferred to the
    /// post-merge multi-hop pass).
    private func resolveChainedReceiver(
        _ memberAccess: MemberAccessExprSyntax, propertyMap: [String: String], enclosingTypeName: String?
    ) -> ResolvedReceiver? {
        let hop = memberAccess.declName.baseName.text
        if memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "self",
           let propertyType = propertyMap[hop] {
            return ResolvedReceiver(receiver: .type(propertyType))
        }
        // A deeper chain (`model.diagrams.method()`, `self.model.method()` when `model` isn't a
        // known-typed property directly): resolve the chain's *head* (everything before this last
        // hop) to a type and defer `hop` to the post-merge pass, which has the full project type
        // graph to look up `hop`'s declared type on the head's type.
        guard let headType = chainHeadType(
            of: memberAccess.base, propertyMap: propertyMap, enclosingTypeName: enclosingTypeName)
        else { return nil }
        return ResolvedReceiver(receiver: .propertyChain(headTypeName: headType, hops: [hop]))
    }

    /// The type of a property-access chain's head (`self`, `Self`, a known-typed property, or a
    /// same-file type name), used to seed `.propertyChain(headTypeName:hops:)` when the final hop
    /// isn't resolvable in-file. Returns `nil` when the head itself isn't provably typed — a chain
    /// starting from an unknown receiver stays dropped, not deferred (only the *last* hop before the
    /// method call defers; a deeper unresolved head is not chased further).
    private func chainHeadType(
        of expr: ExprSyntax?, propertyMap: [String: String], enclosingTypeName: String?
    ) -> String? {
        guard let declRef = expr?.as(DeclReferenceExprSyntax.self) else { return nil }
        let name = declRef.baseName.text
        if name == "self" || name == "Self" {
            return enclosingTypeName
        }
        if let propertyType = propertyMap[name] {
            return propertyType
        }
        return knownTypeNames.contains(name) ? name : nil
    }

    /// The type a `let`/`var` binding provably introduces for receiver resolution, when it can be read
    /// off an explicit annotation (`let x: Foo`), a construction initializer (`let x = Foo()`), or a
    /// same-type method call whose return type is unambiguous (`let x = compute()` / `let x =
    /// self.compute()`, resolved via `methodReturnTypes`). Callers fold this into their property map
    /// so a later `x.method()` resolves to `Foo`.
    func localBinding(
        from binding: PatternBindingSyntax, methodReturnTypes: [String: String] = [:]
    ) -> (name: String, type: String)? {
        guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return nil }
        if let identifier = binding.typeAnnotation?.type.as(IdentifierTypeSyntax.self) {
            return (name, identifier.name.text)
        }
        guard let call = binding.initializer?.value.as(FunctionCallExprSyntax.self) else { return nil }
        if let type = constructedTypeName(call) {
            return (name, type)
        }
        if let methodName = calleeMethodName(call), let returnType = methodReturnTypes[methodName] {
            return (name, returnType)
        }
        return nil
    }

    /// The bare method name of a `compute()` / `self.compute()` call expression's callee, or `nil` for
    /// any other shape (a construction, a static call, a receiver-typed call) — those are handled by
    /// their own resolution paths and must not be double-counted as a same-type method call.
    private func calleeMethodName(_ call: FunctionCallExprSyntax) -> String? {
        let callee = unwrappedCallee(call.calledExpression)
        if let declRef = callee.as(DeclReferenceExprSyntax.self), !isTypeName(declRef.baseName.text) {
            return declRef.baseName.text
        }
        if let memberAccess = callee.as(MemberAccessExprSyntax.self),
           memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "self" {
            return memberAccess.declName.baseName.text
        }
        return nil
    }

    /// The constructed type name of a `Foo(...)` call expression, or `nil` when its callee isn't a
    /// type name (so `bar()` / `Foo.make()` aren't mistaken for constructions).
    private func constructedTypeName(_ call: FunctionCallExprSyntax) -> String? {
        guard let declRef = unwrappedCallee(call.calledExpression).as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        let name = declRef.baseName.text
        return isTypeName(name) ? name : nil
    }
}
