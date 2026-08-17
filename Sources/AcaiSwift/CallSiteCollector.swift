import SwiftSyntax
import AcaiCore

/// What a local/guard-let binding's declared type resolves to: a concrete type name (folded into the
/// scalar `varName → typeName` map), or — when only provable post-merge (cross-file method return,
/// `Type.staticMember` access) — a deferred `CallReceiver` carried to the binding's later use.
enum LocalBindingOrigin {
    case concrete(String)
    case deferred(CallReceiver)
}

/// Resolves body-level facts the sequence/state generators need — call sites, assignments, referenced
/// type names — from individual expression nodes. Holds no traversal state; the visitor drives the
/// walk and hands each node here for interpretation.
struct CallSiteCollector {
    /// Simple names of every type declared in the file, used to recognise `TypeName.method()`
    /// static calls.
    let knownTypeNames: Set<String>

    private let sourceLocations = SourceLocationResolver()
    private let values = SwiftValueClassifier()

    /// A resolvable call site (`receiver.method()`), or `nil` when the receiver can't be resolved and
    /// the call should be dropped. `propertyMap` maps the current type's stored properties to their
    /// declared types. `knownLocalNames` holds every local/parameter declared so far (even with
    /// unprovable type), so such a local isn't mistaken for an unresolved own-property receiver.
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
    /// `CallReceiver` (`localReceiverOriginMap`) because its type couldn't be proven in this file.
    /// Tried only after normal `callSite(from:)` resolution misses.
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

    /// A bare `foo()` — an implicit-`self` method call or a free-function call; can't tell which at
    /// parse time, so records `.selfDispatch` and lets the whole-artifact resolvers match it against
    /// the caller's own methods first, then free functions. A construction or closure-property call
    /// isn't a resolvable target, so it's dropped.
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

    /// Treats a same-file declared type or any capitalised identifier as a type name, so `Foo()`/`UUID()`
    /// read as construction, not a call — cross-file types aren't in `knownTypeNames`, hence the
    /// capitalisation guard (Swift methods are lowerCamelCase).
    func isTypeName(_ name: String) -> Bool {
        knownTypeNames.contains(name) || name.first?.isUppercase == true
    }

    /// Strips `foo<T>()` generic-specialisation and `foo?()` optional-chaining wrappers so the callee
    /// reduces to its underlying `MemberAccessExprSyntax` / `DeclReferenceExprSyntax`.
    func unwrappedCallee(_ expr: ExprSyntax) -> ExprSyntax {
        if let generic = expr.as(GenericSpecializationExprSyntax.self) { return generic.expression }
        if let optional = expr.as(OptionalChainingExprSyntax.self) { return optional.expression }
        return expr
    }

    /// Strips `?`/`!` postfix wrappers so a receiver base reduces to its underlying expression. Swift
    /// parses `x?.foo()` as `MemberAccessExprSyntax(base: OptionalChainingExprSyntax(x), …)` — the `?`
    /// wraps only the base — so every receiver-resolution entry point needs this, not just the callee.
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

    /// A variable assignment recovered from a `SequenceExprSyntax`, or `nil` if it isn't one. The file
    /// is parsed without operator folding, so `x = expr` surfaces as `[target, AssignmentExpr, value…]`,
    /// and compound assignments as `[target, BinaryOperatorExpr(+=), value…]`.
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
        // non-enumerable expression. Plain assignments have exactly one classifiable RHS element;
        // longer tails (chained assignment, unlike a folded ternary) are also non-enumerable.
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

    /// A read of a stored property, or `nil` when the identifier isn't one of the type's properties.
    /// Bare identifiers and the member of a `self.x` access both surface as `DeclReferenceExprSyntax`,
    /// so this records them with `receiver == nil`; consumers filter by name (issue #111).
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
    /// loadInitialState)`) rather than a direct call — reached the same way an implicit-`self` call
    /// would reach it, so it must count as a use even with no `FunctionCallExprSyntax` around it.
    /// Callers guard with `isBareReferenceUse` first. `methodNames` is the enclosing type's own
    /// method-name set from a raw pre-pass, so a forward-declared method is still recognised.
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
    /// enclosing call (already recorded via `FunctionCallExprSyntax`) and not the tail of a qualified
    /// member access (`self.chooseFile`, `object.chooseFile` — not handled as value references).
    func isBareReferenceUse(_ node: DeclReferenceExprSyntax) -> Bool {
        guard var parent = node.parent else { return false }
        if let memberAccess = parent.as(MemberAccessExprSyntax.self), memberAccess.declName.id == node.id {
            return false
        }
        // Walk up through `foo<T>`/`foo?` callee wrappers (mirrors `unwrappedCallee`) so such a call is
        // still recognised as a real call, not double-recorded as a bare reference too.
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

    /// Resolves the declared type for a receiver expression: a known stored property or same-file type
    /// name resolves directly; a capitalised name not known here, or a deeper property chain, defers to
    /// the post-merge pass (`CodeArtifact.resolvingCallSiteReceivers()`). `nil` drops the call.
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
        // Capitalised but not declared in this file: possibly declared elsewhere in the project.
        if name.first?.isUppercase == true {
            return ResolvedReceiver(receiver: .unresolvedTypeName(name))
        }
        // A lowercase identifier unresolvable here is most often the enclosing type's own stored
        // property, declared in a sibling extension file. Deferred unless `name` is already known as
        // a local/parameter with an unprovable type — such a local stays dropped, never guessed as an
        // own-property. A free function has no enclosing type, so also stays dropped.
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
        // A capitalised hop is a nested-type reference, never a property — the whole capitalised
        // prefix is joined into a dotted path (matching this project's `qualifiedName` scheme) since a
        // bare last segment is ambiguous when two unrelated nested types share that simple name.
        // Always deferred to the post-merge pass so an absent/ambiguous match never guesses.
        if hop.first?.isUppercase == true {
            let path = memberAccess.base.flatMap(capitalizedChainPath).map { "\($0).\(hop)" } ?? hop
            return ResolvedReceiver(receiver: .unresolvedTypeName(path))
        }
        // A deeper chain: resolve the chain's head (everything before this last hop) to a type and
        // defer `hop` to the post-merge pass, which has the full project type graph to resolve it.
        if let headType = chainHeadType(
            of: memberAccess.base, propertyMap: propertyMap, enclosingTypeName: enclosingTypeName) {
            return ResolvedReceiver(receiver: .propertyChain(headTypeName: headType, hops: [hop]))
        }
        // Same rationale as the unresolvable-head case in `resolveIdentifierReceiver`.
        if let headName = bareLowercaseIdentifier(memberAccess.base), enclosingTypeName != nil,
           !knownLocalNames.contains(headName) {
            return ResolvedReceiver(receiver: .ownProperty(propertyName: headName, remainingHops: [hop]))
        }
        return nil
    }

    /// A bare, lowercase identifier receiver expression — the shape an unqualified property access takes.
    func bareLowercaseIdentifier(_ expr: ExprSyntax?) -> String? {
        guard let declRef = expr.map(unwrappedReceiverBase)?.as(DeclReferenceExprSyntax.self) else { return nil }
        let name = declRef.baseName.text
        guard name != "self", name != "Self", name.first?.isUppercase != true else { return nil }
        return name
    }

    /// The dotted path of a pure capitalised-identifier chain, or `nil` when `expr` isn't itself such a
    /// chain — only a genuine namespace/type-path prefix is joined, never a value chain that happens
    /// to end in a capitalised segment.
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

    /// The type of a property-access chain's head, used to seed `.propertyChain(headTypeName:hops:)`
    /// when the final hop isn't resolvable in-file. Returns `nil` when the head itself isn't provably
    /// typed — only the last hop before the method call defers; a deeper unresolved head isn't chased.
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
    /// type name (so `bar()` / `Foo.make()` aren't mistaken for constructions).
    func constructedTypeName(_ call: FunctionCallExprSyntax) -> String? {
        guard let declRef = unwrappedCallee(call.calledExpression).as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        let name = declRef.baseName.text
        return isTypeName(name) ? name : nil
    }
}
