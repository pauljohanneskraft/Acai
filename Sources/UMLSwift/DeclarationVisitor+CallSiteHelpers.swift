import SwiftSyntax
import UMLCore

// Stack management and call-site-resolution helpers — in a separate file so `DeclarationVisitor`'s
// main declaration stays within SwiftLint's `file_length`/`type_body_length`.
extension DeclarationVisitor {

    // MARK: - Stack Management

    var currentNamespace: String? {
        typeStack.last?.qualifiedName
    }

    func pushType(_ type: TypeDeclaration, memberBlock: MemberBlockSyntax) {
        typeStack.append(type)
        methodReturnTypeMapStack.append(returnTypeMap(from: memberBlock))
        ambiguousReturnTypeMethodNamesStack.append(ambiguousReturnTypeMethodNames(from: memberBlock))
        methodNameMapStack.append(methodNames(from: memberBlock))
    }

    func popType() {
        guard let completed = typeStack.popLast() else { return }
        methodReturnTypeMapStack.removeLast()
        ambiguousReturnTypeMethodNamesStack.removeLast()
        methodNameMapStack.removeLast()
        if typeStack.isEmpty {
            types.append(completed)
        } else {
            typeStack[typeStack.count - 1].nestedTypes.append(completed)
        }
    }

    /// Builds a `methodName → returnTypeName` map from a type's *direct* member list in one pre-pass
    /// over the raw syntax (not the progressively-accumulated `Member`s), so a forward-declared
    /// method's return type is seen regardless of source order — same rationale as `knownTypeNames`.
    /// Keeps only names with a single, unambiguous return type across all overloads (an overloaded
    /// name with differing return types is dropped rather than guessed).
    func returnTypeMap(from memberBlock: MemberBlockSyntax) -> [String: String] {
        var typesByName: [String: Set<String>] = [:]
        for item in memberBlock.members {
            guard let function = item.decl.as(FunctionDeclSyntax.self),
                  let returnClause = function.signature.returnClause,
                  let name = callSites.simpleIdentifierTypeName(from: returnClause.type)
            else { continue }
            typesByName[function.name.text, default: []].insert(name)
        }
        return typesByName.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    /// Method names with more than one *distinct* return type among this type's own overloads, from
    /// the same raw pre-pass as `returnTypeMap` — `returnTypeMap` silently drops these (an ambiguous
    /// overload has no single inferrable return type), which is indistinguishable from "not declared
    /// in this file at all" unless tracked separately. Consulted so a same-type call whose return type
    /// is genuinely ambiguous (not just cross-file) stays dropped rather than deferred to the
    /// post-merge pass, which resolves per-*type*, not per-overload, and would otherwise guess.
    func ambiguousReturnTypeMethodNames(from memberBlock: MemberBlockSyntax) -> Set<String> {
        var typesByName: [String: Set<String>] = [:]
        for item in memberBlock.members {
            guard let function = item.decl.as(FunctionDeclSyntax.self),
                  let returnClause = function.signature.returnClause,
                  let name = callSites.simpleIdentifierTypeName(from: returnClause.type)
            else { continue }
            typesByName[function.name.text, default: []].insert(name)
        }
        return Set(typesByName.filter { $0.value.count > 1 }.keys)
    }

    /// A type's own method names, from the same raw pre-pass as `returnTypeMap` — feeds
    /// `CallSiteCollector.methodReference`, so a bare method-reference-as-value resolves regardless of
    /// source order.
    func methodNames(from memberBlock: MemberBlockSyntax) -> Set<String> {
        Set(memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self)?.name.text })
    }

    /// Builds a `varName → typeName` map from the stored properties already
    /// extracted for the current type.  Called just before descending into a
    /// function body so we know which receiver names can be resolved.
    ///
    /// When the current type is a protocol extension, also seeds the extended protocol's own
    /// requirement properties (`var x: T { get }`) — the extension's own member list never carries
    /// them (they're declared on the protocol, not the extension), so a default implementation
    /// calling through one (`history.undo()`) would otherwise be unresolvable.
    func buildPropertyMap() -> [String: String] {
        guard let currentType = typeStack.last else { return [:] }
        var map: [String: String] = [:]
        for member in currentType.members where member.kind == .property {
            if let typeName = member.type?.name {
                map[member.name] = typeName
            }
        }
        if currentType.kind == .extension, let extendedProtocol = currentType.extensionOf,
           let requirements = protocolProperties[extendedProtocol] {
            map.merge(requirements) { existing, _ in existing }
        }
        return map
    }

    /// Stored-property array-element types for the current type (`varName → elementTypeName` for
    /// every `[X]`-typed property) — the array-element counterpart to `buildPropertyMap()`, feeding
    /// `CallSiteCollector.arrayElementReceiverType`.
    func buildArrayElementPropertyMap() -> [String: String] {
        guard let currentType = typeStack.last else { return [:] }
        var map: [String: String] = [:]
        for member in currentType.members where member.kind == .property {
            if let type = member.type, type.isArray, let elementName = type.genericArguments.first?.name {
                map[member.name] = elementName
            }
        }
        return map
    }

    /// Resets `callSiteState` to a fresh instance seeded with the property/parameter maps for a new
    /// top-of-body function/initializer about to be walked — shared by `visit(_ node:
    /// FunctionDeclSyntax)` and `visit(_ node: InitializerDeclSyntax)`, which otherwise resolve the
    /// same maps.
    func resetCallSiteState(parameterClause: FunctionParameterClauseSyntax) {
        callSiteState = CallSiteAccumulator(
            propertyMap: buildPropertyMap(),
            arrayElementPropertyMap: buildArrayElementPropertyMap(),
            parameterMap: parameterMap(from: parameterClause),
            knownLocalNames: knownParameterNames(from: parameterClause)
        )
    }

    /// Builds a `paramName → typeName` map from a function/initializer's parameter list, so a
    /// `param.method()` call inside the body resolves. Only parameters with a provable simple type
    /// name are included (mirrors `buildPropertyMap`'s "typed only" bar).
    func parameterMap(from parameterClause: FunctionParameterClauseSyntax) -> [String: String] {
        var map: [String: String] = [:]
        for parameter in signatures.extractParameters(from: parameterClause) {
            if let typeName = parameter.type?.name {
                map[parameter.internalName] = typeName
            }
        }
        return map
    }

    /// `globalName → typeName` for every top-level `let`/`var` with a provable type, built fresh at
    /// each top-level call site so it reflects every global declared so far.
    func topLevelGlobalPropertyMap() -> [String: String] {
        Dictionary(
            globalVariables.compactMap { global in global.type.map { (global.name, $0.name) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Attaches every binding's *initializer* type references (e.g. `= Foo()`) to `members` — the
    /// signature misses these, so this surfaces construction dependencies for the coupling metrics.
    /// Deliberately skips accessor bodies (computed getters): walking a deeply nested `var body: some
    /// View { … }` would recurse far enough to overflow the stack.
    func attachingInitializerReferencedTypes(to members: [Member], from node: VariableDeclSyntax) -> [Member] {
        var referencedSet = Set<String>()
        for binding in node.bindings {
            if let value = binding.initializer?.value {
                referencedSet.formUnion(callSites.referencedTypes(in: value))
            }
        }
        guard !referencedSet.isEmpty else { return members }
        let referenced = Array(referencedSet)
        return members.map { member in
            var copy = member
            copy.referencedTypeNames = referenced
            return copy
        }
    }

    /// Folds a top-level `let`/`var` binding's deferred origin (`Type.staticMember`, e.g. `let
    /// registry = ToolRegistry.standard`) into `topLevelGlobalReceiverOriginMap`, so a later
    /// `registry.method()` call in top-level code resolves — `extractVariable`'s own `Member.type`
    /// (fed into `topLevelGlobalPropertyMap`) stays concrete-only.
    func recordingTopLevelGlobalReceiverOrigins(from bindings: PatternBindingListSyntax) {
        for binding in bindings {
            guard let local = callSites.localBinding(from: binding), case .deferred(let receiver) = local.origin
            else { continue }
            topLevelGlobalReceiverOriginMap[local.name] = receiver
        }
    }

    /// Every parameter's internal name, typed or not — unlike `parameterMap`, which only keeps the
    /// typed ones. Seeds `callSiteState.knownLocalNames` so an untyped parameter still counts as
    /// "known," keeping it from being mistaken for an unresolved own-property receiver.
    func knownParameterNames(from parameterClause: FunctionParameterClauseSyntax) -> Set<String> {
        Set(signatures.extractParameters(from: parameterClause).map(\.internalName))
    }

    /// Merges a nested local function's own parameters into `callSiteState.parameterMap`/
    /// `callSiteState.knownLocalNames` for the remainder of the enclosing function's body — so a call
    /// through one of them (`param.method()`) inside the nested function still resolves.
    func mergeNestedFunctionParameters(from parameterClause: FunctionParameterClauseSyntax) {
        for parameter in signatures.extractParameters(from: parameterClause) {
            callSiteState.knownLocalNames.insert(parameter.internalName)
            if let typeName = parameter.type?.name {
                callSiteState.parameterMap[parameter.internalName] = typeName
            }
        }
    }

    /// Records every binding's name into `callSiteState.knownLocalNames` immediately (unlike the
    /// deferred type resolution in `pendingLocalBindingsStack`, recording the *name* has no
    /// self-shadowing hazard), and returns the bindings whose origin could also be resolved (concrete
    /// or deferred), for the caller to defer.
    func recordingKnownLocalNames(
        from bindings: PatternBindingListSyntax
    ) -> [(name: String, origin: LocalBindingOrigin)] {
        let returnTypes = methodReturnTypeMapStack.last ?? [:]
        let ambiguousMethodNames = ambiguousReturnTypeMethodNamesStack.last ?? []
        var newLocals: [(name: String, origin: LocalBindingOrigin)] = []
        for binding in bindings {
            if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                callSiteState.knownLocalNames.insert(name)
            }
            if let local = callSites.localBinding(
                from: binding, methodReturnTypes: returnTypes, ambiguousMethodNames: ambiguousMethodNames) {
                newLocals.append(local)
            }
        }
        return newLocals
    }

    /// The `guard let x = …` / `if let x = …` analogue of `recordingKnownLocalNames`: records the
    /// name into `callSiteState.knownLocalNames` immediately, and returns the resolved origin (if
    /// provable) for the caller to defer into `callSiteState.localMap`/`localReceiverOriginMap` until
    /// after the initializer has been visited.
    func resolvingConditionBinding(
        from node: OptionalBindingConditionSyntax
    ) -> (name: String, origin: LocalBindingOrigin)? {
        if let name = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
            callSiteState.knownLocalNames.insert(name)
        }
        return callSites.localBinding(
            from: node, methodReturnTypes: methodReturnTypeMapStack.last ?? [:],
            ambiguousMethodNames: ambiguousReturnTypeMethodNamesStack.last ?? [])
    }

    /// Folds a resolved local-binding origin into `callSiteState`: a concrete type name into
    /// `localMap` (as before), or a deferred `CallReceiver` into `localReceiverOriginMap` — the
    /// binding's later use as a receiver (`CallSiteCollector.deferredCallSite`) consults whichever one
    /// has an entry.
    func recordLocalBindingOrigin(_ local: (name: String, origin: LocalBindingOrigin)) {
        switch local.origin {
        case .concrete(let type):
            callSiteState.localMap[local.name] = type
        case .deferred(let receiver):
            callSiteState.localReceiverOriginMap[local.name] = receiver
        }
    }

    /// Call sites gathered from every accessor body of a type-level `var`/`let` declaration, so a
    /// method reached only from a computed property (a SwiftUI `body`, a derived value) is not
    /// mistaken for dead code. Only reached at type scope — `visit` already skips local declarations.
    func collectAccessorCallSites(from node: VariableDeclSyntax) -> [CallSite] {
        guard !typeStack.isEmpty else { return [] }
        let propertyMap = buildPropertyMap()
        var sites: [CallSite] = []
        for binding in node.bindings {
            guard let accessor = binding.accessorBlock else { continue }
            let walker = AccessorCallSiteWalker(
                collector: callSites, propertyMap: propertyMap,
                enclosingTypeName: typeStack.last?.name,
                methodReturnTypes: methodReturnTypeMapStack.last ?? [:],
                methodNames: methodNameMapStack.last ?? [], fileName: fileName)
            walker.walk(accessor)
            sites.append(contentsOf: walker.collected)
        }
        return sites
    }

    /// Call sites made inside a *stored* property's initializer expression (`static let light =
    /// make(isDark: false)`) — the initializer-expression analogue of `collectAccessorCallSites`,
    /// which only ever walks computed accessor bodies. Without this, a call made only from a stored
    /// property's initializer is invisible to the call graph (confirmed false-positive: `DiagramPalette
    /// .make`, reached solely via `static let light = make(isDark: false)`).
    func collectInitializerCallSites(from node: VariableDeclSyntax) -> [CallSite] {
        guard !typeStack.isEmpty else { return [] }
        let propertyMap = buildPropertyMap()
        var sites: [CallSite] = []
        for binding in node.bindings {
            guard let value = binding.initializer?.value else { continue }
            let walker = AccessorCallSiteWalker(
                collector: callSites, propertyMap: propertyMap,
                enclosingTypeName: typeStack.last?.name,
                methodReturnTypes: methodReturnTypeMapStack.last ?? [:],
                methodNames: methodNameMapStack.last ?? [], fileName: fileName)
            walker.walk(value)
            sites.append(contentsOf: walker.collected)
        }
        return sites
    }

    /// Binds an implicit-`$0` iteration closure's parameter to the iterated array property's
    /// *element* type (`addedRelationships.map { $0.reportPhrase() }`) and records the resulting
    /// call sites into `callSiteState.pendingCallSites`. A no-op when `node` isn't such a closure
    /// (`CallSiteCollector.iterationClosure(in:)`) or its receiver isn't a resolvable array property
    /// (`arrayElementReceiverType`). Called from `visit(_ node: FunctionCallExprSyntax)`, which still
    /// lets the default child traversal descend into the closure afterwards — that redundant visit
    /// re-encounters `$0.method()` and simply fails to resolve `$0` (no binding in scope there), so
    /// nothing is double-counted.
    func recordingIterationClosureCallSites(in node: FunctionCallExprSyntax) {
        guard let (receiverBase, closure) = callSites.iterationClosure(in: node),
              let elementReceiver = callSites.arrayElementReceiverType(
                of: receiverBase, arrayElementPropertyMap: callSiteState.arrayElementPropertyMap,
                enclosingTypeName: typeStack.last?.name, knownLocalNames: callSiteState.knownLocalNames)
        else { return }
        let walker = Closure0CallSiteWalker(elementReceiver: elementReceiver, fileName: fileName)
        walker.walk(closure)
        callSiteState.pendingCallSites.append(contentsOf: walker.collected)
    }
}
