import SwiftSyntax
import AcaiCore

/// Local/guard-let binding type resolution.
extension CallSiteCollector {
    /// The type a `let`/`var` binding provably introduces for receiver resolution: read off an explicit
    /// annotation, a construction initializer, or a same-type method call (resolved via
    /// `methodReturnTypes` when unambiguous, or deferred via `.ownMethodReturn` when declared in a
    /// sibling extension file — but not when `ambiguousMethodNames` marks it genuinely unresolvable).
    /// Callers fold `.concrete` into their property map and `.deferred` into their receiver-origin map.
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

    /// The `guard let x = …` / `if let x = …` analogue of ``localBinding(from:methodReturnTypes:)``.
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

    private func localBindingType(
        name: String, typeAnnotation: TypeSyntax?, initializerValue: ExprSyntax?,
        methodReturnTypes: [String: String], ambiguousMethodNames: Set<String>
    ) -> (name: String, origin: LocalBindingOrigin)? {
        if let typeAnnotation, let typeName = simpleIdentifierTypeName(from: typeAnnotation) {
            return (name, .concrete(typeName))
        }
        // `Type.staticMember` (no call parens, e.g. `ToolRegistry.standard`) — deferred via
        // `.propertyChain`, which resolves this shape project-wide through the post-merge pass.
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
        // A genuinely ambiguous same-type overload has no single answer even post-merge — stays
        // dropped, not deferred, unlike the cross-file case below.
        guard !ambiguousMethodNames.contains(methodName) else { return nil }
        // A same-type call whose return type isn't provable in this file — most often because the
        // method is declared in a sibling extension file. Deferred to the post-merge pass.
        return (name, .deferred(.ownMethodReturn(methodName: methodName, remainingHops: [])))
    }

    /// The simple type name of `typeSyntax`, unwrapping `Optional`/`ImplicitlyUnwrappedOptional` sugar
    /// first. Deliberately narrower than `TypeReferenceExtractor`: a tuple/array/dictionary/function
    /// type is never a resolvable receiver, so those stay `nil` here even though `TypeReferenceExtractor`
    /// gives them a synthetic display name for other purposes (diagram type annotations).
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
    /// any other shape — those are handled by their own resolution paths.
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
