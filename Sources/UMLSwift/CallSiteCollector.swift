import SwiftSyntax
import UMLCore

/// What a local/guard-let binding's declared type resolves to: a concrete simple type name (folded
/// into a scalar `varName → typeName` map, same as a stored property), or — when only provable
/// post-merge (a cross-file same-type method return, a `Type.staticMember` access) — a deferred
/// `CallReceiver` descriptor carried forward to the binding's later use as a receiver.
enum LocalBindingOrigin {
    case concrete(String)
    case deferred(CallReceiver)
}

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
    /// `storedPropertyName → declaredTypeName` map. `knownLocalNames` is every local/parameter name
    /// declared so far in the current body, *whether or not* its type was provable (e.g. a local
    /// initialized from an ambiguous overload) — consulted only to keep such a local from being
    /// mistaken for an unresolved own-property receiver (see `resolveIdentifierReceiver`).
    func callSite(
        from node: FunctionCallExprSyntax, propertyMap: [String: String],
        enclosingTypeName: String?, knownLocalNames: Set<String> = [], fileName: String
    ) -> CallSite? {
        let callee = unwrappedCallee(node.calledExpression)
        if let memberAccess = callee.as(MemberAccessExprSyntax.self) {
            let methodName = memberAccess.declName.baseName.text
            guard let resolved = resolveReceiver(
                from: memberAccess.base, propertyMap: propertyMap,
                enclosingTypeName: enclosingTypeName, knownLocalNames: knownLocalNames) else { return nil }
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

    /// A call site whose receiver is a local/guard-let/global binding previously deferred to a
    /// `CallReceiver` descriptor (`localReceiverOriginMap`) rather than a concrete type name — the
    /// binding's own type couldn't be proven in this file, so its later use as a receiver carries that
    /// same deferred descriptor forward rather than being dropped. Tried only after normal
    /// `callSite(from:)` resolution misses.
    func deferredCallSite(
        from node: FunctionCallExprSyntax, localReceiverOriginMap: [String: CallReceiver], fileName: String
    ) -> CallSite? {
        guard !localReceiverOriginMap.isEmpty,
              let memberAccess = unwrappedCallee(node.calledExpression).as(MemberAccessExprSyntax.self),
              let name = bareLowercaseIdentifier(memberAccess.base),
              let origin = localReceiverOriginMap[name]
        else { return nil }
        return CallSite(
            receiver: origin, methodName: memberAccess.declName.baseName.text,
            location: sourceLocations.sourceLocation(of: node, fileName: fileName)
        )
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
    /// hence the capitalisation guard; Swift methods are lowerCamelCase by convention. Not `private`:
    /// also used from `CallSiteCollector+LocalBindings.swift`.
    func isTypeName(_ name: String) -> Bool {
        knownTypeNames.contains(name) || name.first?.isUppercase == true
    }

    /// Strips `foo<T>()` generic-specialisation and `foo?()` optional-chaining wrappers so the callee
    /// reduces to its underlying `MemberAccessExprSyntax` / `DeclReferenceExprSyntax`. Not `private`:
    /// also used from `CallSiteCollector+IterationClosures.swift`.
    func unwrappedCallee(_ expr: ExprSyntax) -> ExprSyntax {
        if let generic = expr.as(GenericSpecializationExprSyntax.self) { return generic.expression }
        if let optional = expr.as(OptionalChainingExprSyntax.self) { return optional.expression }
        return expr
    }

    /// Strips `?`/`!` postfix wrappers so a receiver base (`self?`, `weakRef?`, `a?.b?`) reduces to
    /// its underlying identifier/member-access expression. Swift parses `x?.foo()` as
    /// `MemberAccessExprSyntax(base: OptionalChainingExprSyntax(x), …)` — the `?` wraps only the base,
    /// not the whole chain — so every receiver-resolution entry point needs this, not just the callee.
    /// Loops since `?`/`!` can interleave (`a?.b!.c`).
    private func unwrappedReceiverBase(_ expr: ExprSyntax) -> ExprSyntax {
        var current = expr
        while true {
            if let optional = current.as(OptionalChainingExprSyntax.self) {
                current = optional.expression
            } else if let forced = current.as(ForceUnwrapExprSyntax.self) {
                current = forced.expression
            } else {
                return current
            }
        }
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

    /// A bare method name used as a first-class value (`action: chooseFile`, `.onAppear(perform:
    /// loadInitialState)`, a label-disambiguated reference like `participantKind(for:)`) rather than a
    /// direct call — the method is reached the same way a `self`-implicit call would reach it, so it
    /// must count as a use even though no `FunctionCallExprSyntax` wraps it here. Callers guard with
    /// `isBareReferenceUse` first; only a node that isn't a real call's callee and isn't the tail of a
    /// qualified member access reaches here — restricted to that shape because a member-access
    /// reference (`object.method`, no call) isn't handled yet. `methodNames` is the enclosing type's
    /// own method-name set (a raw pre-pass, so a forward-declared method is still recognised, mirroring
    /// `returnTypeMap`).
    func methodReference(
        from node: DeclReferenceExprSyntax, propertyMap: [String: String], methodNames: Set<String>,
        fileName: String
    ) -> CallSite? {
        let name = node.baseName.text
        guard propertyMap[name] == nil, methodNames.contains(name) else { return nil }
        return CallSite(
            receiver: .selfDispatch,
            methodName: name,
            location: sourceLocations.sourceLocation(of: node, fileName: fileName)
        )
    }

    /// Whether `node` is a genuinely bare identifier reference — not the callee of its immediately
    /// enclosing call (`chooseFile()`, `maybe?()`, `render<T>()` — already recorded from the
    /// `FunctionCallExprSyntax` it's part of) and not the tail of a qualified member access
    /// (`self.chooseFile`, `object.chooseFile` — member-access references as values aren't handled;
    /// scoped out since none of the audited false positives need it). Shared by both call-site walkers
    /// (`DeclarationVisitor`, `AccessorCallSiteWalker`) so the shape check lives in one place.
    func isBareReferenceUse(_ node: DeclReferenceExprSyntax) -> Bool {
        guard var parent = node.parent else { return false }
        if let memberAccess = parent.as(MemberAccessExprSyntax.self), memberAccess.declName.id == node.id {
            return false
        }
        // Walk up through `foo<T>` / `foo?` callee wrappers (mirrors `unwrappedCallee`) so a call whose
        // callee is decorated this way (`maybe?()`, `render<T>()`) is still recognised as a real call,
        // not double-recorded as a bare reference on top of it.
        var childID = node.id
        while true {
            if let call = parent.as(FunctionCallExprSyntax.self) {
                return call.calledExpression.id != childID
            }
            guard parent.is(OptionalChainingExprSyntax.self) || parent.is(GenericSpecializationExprSyntax.self),
                  let grandparent = parent.parent else {
                return true
            }
            childID = parent.id
            parent = grandparent
        }
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
        from base: ExprSyntax?, propertyMap: [String: String], enclosingTypeName: String?,
        knownLocalNames: Set<String>
    ) -> ResolvedReceiver? {
        guard let base else { return nil }
        let unwrapped = unwrappedReceiverBase(base)

        if let declRef = unwrapped.as(DeclReferenceExprSyntax.self) {
            return resolveIdentifierReceiver(
                declRef, propertyMap: propertyMap, enclosingTypeName: enclosingTypeName,
                knownLocalNames: knownLocalNames)
        }

        if let memberAccess = unwrapped.as(MemberAccessExprSyntax.self) {
            return resolveChainedReceiver(
                memberAccess, propertyMap: propertyMap, enclosingTypeName: enclosingTypeName,
                knownLocalNames: knownLocalNames)
        }

        // `Foo(...).method()` — a call on a freshly constructed value resolves to `Foo`.
        if let call = unwrapped.as(FunctionCallExprSyntax.self), let type = constructedTypeName(call) {
            return ResolvedReceiver(receiver: .type(type))
        }

        return nil
    }

    /// Resolves a bare-identifier receiver (`self`, `Self`, a known property, a same-file type name,
    /// or a capitalised name deferred to the post-merge cross-file pass).
    private func resolveIdentifierReceiver(
        _ declRef: DeclReferenceExprSyntax, propertyMap: [String: String], enclosingTypeName: String?,
        knownLocalNames: Set<String>
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
        // A lowercase identifier not resolvable in this file: most often the enclosing type's own
        // stored property, declared in a sibling `extension` block this file doesn't see (this
        // project's own convention — `Type.swift` + `Type+Feature.swift`). Deferred, not dropped,
        // when an enclosing type exists to check — but only when `name` isn't already known to be a
        // local/parameter in this body (e.g. a local whose *type* couldn't be inferred, from an
        // ambiguous overload or a tuple return): such a local must stay dropped, not be guessed at
        // as an own-property. A free function has no enclosing type either way, so stays dropped.
        if enclosingTypeName != nil, !knownLocalNames.contains(name) {
            return ResolvedReceiver(receiver: .ownProperty(propertyName: name, remainingHops: []))
        }
        return nil
    }

    /// Resolves a member-access receiver (`self.prop.method()`, or a deeper chain deferred to the
    /// post-merge multi-hop pass).
    private func resolveChainedReceiver(
        _ memberAccess: MemberAccessExprSyntax, propertyMap: [String: String], enclosingTypeName: String?,
        knownLocalNames: Set<String>
    ) -> ResolvedReceiver? {
        let hop = memberAccess.declName.baseName.text
        let unwrappedBase = memberAccess.base.map(unwrappedReceiverBase)
        if unwrappedBase?.as(DeclReferenceExprSyntax.self)?.baseName.text == "self",
           let propertyType = propertyMap[hop] {
            return ResolvedReceiver(receiver: .type(propertyType))
        }
        // A capitalised hop is a nested-type reference, never a property — whatever precedes it
        // (`FreeformDiagram.Node.Content.method()`) is a namespace/type-path prefix, not a value
        // chain to walk. The *whole* capitalised prefix is joined into a dotted path (matching this
        // project's `qualifiedName` scheme, `"\(enclosingPath).\(name)"`, no module prefix) rather
        // than just using the bare last segment — a bare "Content" is ambiguous when two unrelated
        // nested types share that simple name (confirmed in this project: `GeneratedDiagram.Content`
        // vs. `FreeformDiagram.Node.Content`), while the full path disambiguates via an exact
        // `qualifiedName` match. Always deferred (never eager `.type`) to the post-merge pass, so an
        // absent/ambiguous match never guesses.
        if hop.first?.isUppercase == true {
            let path = memberAccess.base.flatMap(capitalizedChainPath).map { "\($0).\(hop)" } ?? hop
            return ResolvedReceiver(receiver: .unresolvedTypeName(path))
        }
        // A deeper chain (`model.diagrams.method()`, `self.model.method()` when `model` isn't a
        // known-typed property directly): resolve the chain's *head* (everything before this last
        // hop) to a type and defer `hop` to the post-merge pass, which has the full project type
        // graph to look up `hop`'s declared type on the head's type.
        if let headType = chainHeadType(
            of: memberAccess.base, propertyMap: propertyMap, enclosingTypeName: enclosingTypeName) {
            return ResolvedReceiver(receiver: .propertyChain(headTypeName: headType, hops: [hop]))
        }
        // The chain's head isn't resolvable in this file either — most often the enclosing type's
        // own stored property, declared in a sibling `extension` block (same rationale as
        // `resolveIdentifierReceiver`'s single-hop case, including the known-local exclusion).
        // Defer the whole chain — head plus this hop — to the post-merge pass, which looks the head
        // property up on the fully-merged type.
        if let headName = bareLowercaseIdentifier(memberAccess.base), enclosingTypeName != nil,
           !knownLocalNames.contains(headName) {
            return ResolvedReceiver(receiver: .ownProperty(propertyName: headName, remainingHops: [hop]))
        }
        return nil
    }

    /// A bare, lowercase identifier receiver expression — the shape an unqualified property access
    /// takes (as opposed to `self`/`Self`/a capitalised type name, each handled by their own branch).
    /// Not `private`: also used from `CallSiteCollector+IterationClosures.swift`.
    func bareLowercaseIdentifier(_ expr: ExprSyntax?) -> String? {
        guard let declRef = expr.map(unwrappedReceiverBase)?.as(DeclReferenceExprSyntax.self) else { return nil }
        let name = declRef.baseName.text
        guard name != "self", name != "Self", name.first?.isUppercase != true else { return nil }
        return name
    }

    /// The dotted path of a pure capitalised-identifier chain (`FreeformDiagram.Node` for the base of
    /// `FreeformDiagram.Node.Content`), or `nil` when `expr` isn't itself such a chain (`self`, a
    /// lowercase property, a call) — only a genuine namespace/type-path prefix is joined, never a
    /// value chain that happens to end in a capitalised segment.
    private func capitalizedChainPath(_ expr: ExprSyntax) -> String? {
        let unwrapped = unwrappedReceiverBase(expr)
        if let declRef = unwrapped.as(DeclReferenceExprSyntax.self) {
            let name = declRef.baseName.text
            return name.first?.isUppercase == true ? name : nil
        }
        if let memberAccess = unwrapped.as(MemberAccessExprSyntax.self) {
            let name = memberAccess.declName.baseName.text
            guard name.first?.isUppercase == true, let base = memberAccess.base,
                  let basePath = capitalizedChainPath(base) else { return nil }
            return "\(basePath).\(name)"
        }
        return nil
    }

    /// The type of a property-access chain's head (`self`, `Self`, a known-typed property, or a
    /// same-file type name), used to seed `.propertyChain(headTypeName:hops:)` when the final hop
    /// isn't resolvable in-file. Returns `nil` when the head itself isn't provably typed — a chain
    /// starting from an unknown receiver stays dropped, not deferred (only the *last* hop before the
    /// method call defers; a deeper unresolved head is not chased further).
    private func chainHeadType(
        of expr: ExprSyntax?, propertyMap: [String: String], enclosingTypeName: String?
    ) -> String? {
        guard let declRef = expr.map(unwrappedReceiverBase)?.as(DeclReferenceExprSyntax.self) else { return nil }
        let name = declRef.baseName.text
        if name == "self" || name == "Self" {
            return enclosingTypeName
        }
        if let propertyType = propertyMap[name] {
            return propertyType
        }
        return knownTypeNames.contains(name) ? name : nil
    }

    /// The constructed type name of a `Foo(...)` call expression, or `nil` when its callee isn't a
    /// type name (so `bar()` / `Foo.make()` aren't mistaken for constructions). Not `private`: also
    /// used from `CallSiteCollector+LocalBindings.swift`.
    func constructedTypeName(_ call: FunctionCallExprSyntax) -> String? {
        guard let declRef = unwrappedCallee(call.calledExpression).as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        let name = declRef.baseName.text
        return isTypeName(name) ? name : nil
    }
}
