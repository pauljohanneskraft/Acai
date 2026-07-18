import SwiftSyntax
import AcaiCore

/// Local/guard-let binding type resolution — split out of `CallSiteCollector.swift` to keep that
/// file under the project's length limits.
extension CallSiteCollector {
    /// The type a `let`/`var` binding provably introduces for receiver resolution, when it can be read
    /// off an explicit annotation (`let x: Foo`), a construction initializer (`let x = Foo()`), or a
    /// same-type method call (resolved via `methodReturnTypes` when unambiguous, or deferred to the
    /// post-merge pass via `.ownMethodReturn` when the method is declared in a sibling extension file
    /// this file doesn't see — but *not* when `ambiguousMethodNames` says the method has more than one
    /// same-type overload with different return types, since that's genuinely unresolvable, not merely
    /// cross-file). Callers fold `.concrete` into their property map and `.deferred` into their
    /// receiver-origin map, so a later `x.method()` resolves either way.
    func localBinding(
        from binding: PatternBindingSyntax, methodReturnTypes: [String: String] = [:],
        ambiguousMethodNames: Set<String> = []
    ) -> (name: String, origin: LocalBindingOrigin)? {
        guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return nil }
        return localBindingType(
            name: name, typeAnnotation: binding.typeAnnotation?.type,
            initializerValue: binding.initializer?.value, methodReturnTypes: methodReturnTypes,
            ambiguousMethodNames: ambiguousMethodNames)
    }

    /// The `guard let x = …` / `if let x = …` analogue of ``localBinding(from:methodReturnTypes:)`` —
    /// same provable shapes, read off `OptionalBindingConditionSyntax`'s equivalent fields. A
    /// `guard let diagram = generatedDiagram(for: id)` binding is exactly as resolvable as a plain
    /// `let diagram = generatedDiagram(for: id)`; the only difference is which syntax node Swift uses.
    func localBinding(
        from binding: OptionalBindingConditionSyntax, methodReturnTypes: [String: String] = [:],
        ambiguousMethodNames: Set<String> = []
    ) -> (name: String, origin: LocalBindingOrigin)? {
        guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return nil }
        return localBindingType(
            name: name, typeAnnotation: binding.typeAnnotation?.type,
            initializerValue: binding.initializer?.value, methodReturnTypes: methodReturnTypes,
            ambiguousMethodNames: ambiguousMethodNames)
    }

    /// Shared resolution behind both `localBinding(from:)` overloads — see their docs for the provable
    /// shapes.
    private func localBindingType(
        name: String, typeAnnotation: TypeSyntax?, initializerValue: ExprSyntax?,
        methodReturnTypes: [String: String], ambiguousMethodNames: Set<String>
    ) -> (name: String, origin: LocalBindingOrigin)? {
        if let typeAnnotation, let typeName = simpleIdentifierTypeName(from: typeAnnotation) {
            return (name, .concrete(typeName))
        }
        // `Type.staticMember` (no call parens, e.g. `ToolRegistry.standard`) — deferred via
        // `.propertyChain`, which already resolves this shape project-wide through the post-merge
        // pass regardless of whether `Type` is declared in this file.
        if let memberAccess = initializerValue?.as(MemberAccessExprSyntax.self),
           let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
           base.baseName.text.first?.isUppercase == true {
            return (name, .deferred(.propertyChain(
                headTypeName: base.baseName.text, hops: [memberAccess.declName.baseName.text])))
        }
        guard let call = initializerValue?.as(FunctionCallExprSyntax.self) else { return nil }
        if let type = constructedTypeName(call) {
            return (name, .concrete(type))
        }
        guard let methodName = calleeMethodName(call) else { return nil }
        if let returnType = methodReturnTypes[methodName] {
            return (name, .concrete(returnType))
        }
        // A genuinely ambiguous same-type overload (multiple same-name methods, different return
        // types, all declared in this file) has no single answer even post-merge — stays dropped, not
        // deferred, unlike the cross-file case below.
        guard !ambiguousMethodNames.contains(methodName) else { return nil }
        // A same-type call (`compute()` / `self.compute()`), but its return type isn't provable in
        // this file — most often because the method is declared in a sibling extension file. Deferred
        // to the post-merge pass rather than dropped (RC cross-file-method-return).
        return (name, .deferred(.ownMethodReturn(methodName: methodName, remainingHops: [])))
    }

    /// The simple type name of `typeSyntax`, when it resolves to a plain named type — unwrapping
    /// `Optional`/`ImplicitlyUnwrappedOptional` sugar (`Foo?`/`Foo!`) first, so an optional-returning
    /// method or optional-annotated local still resolves. Deliberately narrower than
    /// `TypeReferenceExtractor`: a tuple/array/dictionary/function/composition type is never a
    /// resolvable receiver (no `TypeDeclaration` will ever carry a name like `"(Widget, Int)"`), so
    /// those must stay `nil` here even though `TypeReferenceExtractor` gives them a synthetic display
    /// name for other purposes (diagram type annotations).
    func simpleIdentifierTypeName(from typeSyntax: TypeSyntax) -> String? {
        if let optional = typeSyntax.as(OptionalTypeSyntax.self) {
            return simpleIdentifierTypeName(from: optional.wrappedType)
        }
        if let implicitlyUnwrapped = typeSyntax.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return simpleIdentifierTypeName(from: implicitlyUnwrapped.wrappedType)
        }
        return typeSyntax.as(IdentifierTypeSyntax.self)?.name.text
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
}
