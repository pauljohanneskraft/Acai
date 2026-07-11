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
        from node: FunctionCallExprSyntax, propertyMap: [String: String], fileName: String
    ) -> CallSite? {
        let callee = unwrappedCallee(node.calledExpression)
        if let memberAccess = callee.as(MemberAccessExprSyntax.self) {
            let methodName = memberAccess.declName.baseName.text
            guard let resolved = resolveReceiver(
                from: memberAccess.base, propertyMap: propertyMap) else { return nil }
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
    /// Handles (only when provably resolvable — otherwise returns `nil`, dropping the call):
    /// - `varName.method()` — known stored property → its declared type (`.type`),
    /// - `self.varName.method()` — strips the leading `self.` then looks up the property (`.type`),
    /// - `self.method()` — a call on the enclosing instance (`.selfDispatch`),
    /// - `TypeName.method()` — `TypeName` is a known type → a static call (`.type`).
    private func resolveReceiver(
        from base: ExprSyntax?, propertyMap: [String: String]
    ) -> ResolvedReceiver? {
        guard let base else { return nil }

        if let declRef = base.as(DeclReferenceExprSyntax.self) {
            let name = declRef.baseName.text
            if name == "self" {
                return ResolvedReceiver(receiver: .selfDispatch)
            }
            if let propertyType = propertyMap[name] {
                return ResolvedReceiver(receiver: .type(propertyType))
            }
            if knownTypeNames.contains(name) {
                return ResolvedReceiver(receiver: .type(name))
            }
            return nil
        }

        if let memberAccess = base.as(MemberAccessExprSyntax.self),
           memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "self",
           let propertyType = propertyMap[memberAccess.declName.baseName.text] {
            return ResolvedReceiver(receiver: .type(propertyType))
        }

        // `Foo(...).method()` — a call on a freshly constructed value resolves to `Foo`.
        if let call = base.as(FunctionCallExprSyntax.self), let type = constructedTypeName(call) {
            return ResolvedReceiver(receiver: .type(type))
        }

        return nil
    }

    /// The type a `let`/`var` binding provably introduces for receiver resolution, when it can be read
    /// off an explicit annotation (`let x: Foo`) or a construction initializer (`let x = Foo()`).
    /// Callers fold this into their property map so a later `x.method()` resolves to `Foo`.
    func localBinding(from binding: PatternBindingSyntax) -> (name: String, type: String)? {
        guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return nil }
        if let identifier = binding.typeAnnotation?.type.as(IdentifierTypeSyntax.self) {
            return (name, identifier.name.text)
        }
        if let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
           let type = constructedTypeName(call) {
            return (name, type)
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
