import SwiftSyntax
import AcaiCore

/// Per-function-body call-site-collection state: the property/parameter/local maps a call-site
/// receiver resolves against, and the buffers a body's calls/assignments/field-reads accumulate into
/// before folding into its `Member`. Grouped into one value so resetting it (new top-of-body
/// function/initializer, or once finalized) is a single assignment.
struct CallSiteAccumulator {
    var pendingCallSites: [CallSite] = []
    var pendingAssignments: [VariableAssignment] = []
    var pendingFieldReads: [FieldAccess] = []
    /// Stored-property name → declared type name for the current type.
    var propertyMap: [String: String] = [:]
    /// Stored-property name → declared element type, for array-typed (`[X]`) properties. Separate
    /// from `propertyMap`: an array's element is only a valid receiver inside an iteration closure's
    /// implicit `$0`, never a direct call on the property itself.
    var arrayElementPropertyMap: [String: String] = [:]
    /// Local-variable name → provable declared type within the current body. Separate from
    /// `propertyMap`: locals are call-site receivers, not field reads.
    var localMap: [String: String] = [:]
    /// Local/guard-let name → deferred `CallReceiver`, for a binding whose type couldn't be proven
    /// concretely in this file but is resolvable post-merge. Consulted only after `localMap` misses.
    var localReceiverOriginMap: [String: CallReceiver] = [:]
    /// Current function/initializer's parameter name → declared type. Separate from `propertyMap` for
    /// the same reason as `localMap`.
    var parameterMap: [String: String] = [:]
    /// Every local/parameter name declared so far, whether or not its type was provable — unlike
    /// `localMap`/`parameterMap`. Consulted so a local whose type inference failed isn't mistaken for
    /// an unresolved own-property receiver: both look identical (a lowercase name, no map entry).
    var knownLocalNames: Set<String> = []
}

/// Where a `FunctionCallExprSyntax` was found, as `DeclarationVisitor` tracks it: inside a function or
/// closure body (receivers resolve against the current body's property/parameter/local maps), at bare
/// top-level script scope (receivers resolve against `topLevelGlobalReceiverOriginMap` instead), or
/// neither (a call expression outside any function body and inside a type, e.g. a default parameter
/// value — not a site `recordCallSite` attaches anywhere).
enum CallSiteScope {
    case functionBody
    case fileScope
    case other
}

/// Owns everything `DeclarationVisitor` needs to collect call sites, assignments and field reads
/// while it walks a file: the per-function-body accumulator above, the deferred local/condition
/// bindings a self-referential or shadowing initializer requires, the top-level (script-style) call
/// collection, and the per-type method-name/return-type lookups those resolutions need.
///
/// Expression-shape interpretation itself stays in `CallSiteCollector` (held here, stateless); this
/// tracker is the traversal-state counterpart the visitor drives through its own push/pop and
/// begin/end calls, supplying the type/member context (property maps, enclosing type name) it
/// doesn't own itself.
final class CallSiteTracker {
    private(set) var callSiteState = CallSiteAccumulator()
    private(set) var topLevelCallSites: [CallSite] = []
    private(set) var topLevelGlobalReceiverOriginMap: [String: CallReceiver] = [:]

    private var pendingLocalBindingsStack: [[(name: String, origin: LocalBindingOrigin)]] = []
    private var pendingConditionBindingsStack: [(name: String, origin: LocalBindingOrigin)?] = []

    /// Mirrors `DeclarationVisitor.typeStack`: each type's `methodName → returnType` map, pre-passed so
    /// a forward-declared method's return type is seen too.
    private var methodReturnTypeMapStack: [[String: String]] = []
    /// Mirrors `DeclarationVisitor.typeStack`: each type's own method names with an ambiguous
    /// (multi-)return-type overload, so those are never mistaken for a cross-file method and deferred.
    private var ambiguousReturnTypeMethodNamesStack: [Set<String>] = []
    /// Mirrors `DeclarationVisitor.typeStack`: each type's own method names, so a bare
    /// method-reference-as-value (`action: chooseFile`) resolves regardless of declaration order.
    private var methodNameMapStack: [Set<String>] = []

    let callSites: CallSiteCollector
    private let signatures = DeclarationSignatureExtractor()

    init(knownTypeNames: Set<String>) {
        self.callSites = CallSiteCollector(knownTypeNames: knownTypeNames)
    }

    private var currentMethodReturnTypes: [String: String] { methodReturnTypeMapStack.last ?? [:] }
    private var currentAmbiguousReturnTypeMethodNames: Set<String> { ambiguousReturnTypeMethodNamesStack.last ?? [] }
    var currentMethodNames: Set<String> { methodNameMapStack.last ?? [] }

    // MARK: - Type scope, driven by `DeclarationVisitor.pushType`/`popType`

    func pushTypeScope(memberBlock: MemberBlockSyntax) {
        methodReturnTypeMapStack.append(returnTypeMap(from: memberBlock))
        ambiguousReturnTypeMethodNamesStack.append(ambiguousReturnTypeMethodNames(from: memberBlock))
        methodNameMapStack.append(methodNames(from: memberBlock))
    }

    func popTypeScope() {
        methodReturnTypeMapStack.removeLast()
        ambiguousReturnTypeMethodNamesStack.removeLast()
        methodNameMapStack.removeLast()
    }

    /// Builds a `methodName → returnTypeName` map from a type's direct member list in one pre-pass
    /// over the raw syntax, so a forward-declared method's return type is seen regardless of source
    /// order. Keeps only names with a single, unambiguous return type across overloads.
    private func returnTypeMap(from memberBlock: MemberBlockSyntax) -> [String: String] {
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

    /// Method names `returnTypeMap` silently drops for having more than one distinct return type among
    /// overloads — tracked separately so such a name is never deferred to the post-merge pass, which
    /// resolves per-type and would otherwise guess.
    private func ambiguousReturnTypeMethodNames(from memberBlock: MemberBlockSyntax) -> Set<String> {
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
    private func methodNames(from memberBlock: MemberBlockSyntax) -> Set<String> {
        Set(memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self)?.name.text })
    }

    // MARK: - Function-body state

    /// Seeds `callSiteState` fresh for a new top-of-body function/initializer. `propertyMap` and
    /// `arrayElementPropertyMap` come from the caller, which alone knows the current type's members.
    func resetCallSiteState(
        propertyMap: [String: String], arrayElementPropertyMap: [String: String],
        parameterClause: FunctionParameterClauseSyntax
    ) {
        callSiteState = CallSiteAccumulator(
            propertyMap: propertyMap,
            arrayElementPropertyMap: arrayElementPropertyMap,
            parameterMap: parameterMap(from: parameterClause),
            knownLocalNames: knownParameterNames(from: parameterClause)
        )
    }

    /// Clears `callSiteState` once a top-of-body function/initializer has folded its accumulated data
    /// into a `Member`.
    func clearCallSiteState() {
        callSiteState = CallSiteAccumulator()
    }

    /// Builds a `paramName → typeName` map from a function/initializer's parameter list, so a
    /// `param.method()` call inside the body resolves. Only provably-typed parameters are included.
    private func parameterMap(from parameterClause: FunctionParameterClauseSyntax) -> [String: String] {
        var map: [String: String] = [:]
        for parameter in signatures.extractParameters(from: parameterClause) {
            if let typeName = parameter.type?.name {
                map[parameter.internalName] = typeName
            }
        }
        return map
    }

    /// Every parameter's internal name, typed or not — unlike `parameterMap`. Seeds
    /// `callSiteState.knownLocalNames` so an untyped parameter isn't mistaken for an unresolved
    /// own-property receiver.
    private func knownParameterNames(from parameterClause: FunctionParameterClauseSyntax) -> Set<String> {
        Set(signatures.extractParameters(from: parameterClause).map(\.internalName))
    }

    /// Merges a nested local function's own parameters into `callSiteState`, so a call through one of
    /// them resolves inside the nested function.
    func mergeNestedFunctionParameters(from parameterClause: FunctionParameterClauseSyntax) {
        for parameter in signatures.extractParameters(from: parameterClause) {
            callSiteState.knownLocalNames.insert(parameter.internalName)
            if let typeName = parameter.type?.name {
                callSiteState.parameterMap[parameter.internalName] = typeName
            }
        }
    }

    // MARK: - Local & condition bindings

    /// Records every binding's name into `callSiteState.knownLocalNames` immediately — recording just
    /// the name has no self-shadowing hazard — and defers the bindings whose origin could also be
    /// resolved until `endLocalBindings()`, once their initializer has been fully visited (Swift
    /// scoping doesn't put a name in scope until its own initializer finishes, so `let size = size(for:
    /// id)` must resolve the RHS against the outer `size` method, not the not-yet-in-scope local).
    func beginLocalBindings(_ bindings: PatternBindingListSyntax) {
        pendingLocalBindingsStack.append(recordingKnownLocalNames(from: bindings))
    }

    func endLocalBindings() {
        for local in pendingLocalBindingsStack.removeLast() {
            recordLocalBindingOrigin(local)
        }
    }

    /// The `guard let x = …` / `if let x = …` analogue of `beginLocalBindings`: a shadowing initializer
    /// (`guard let self = self else { return }`) must resolve its RHS `self` against the outer scope,
    /// not the new local, hence the same deferral until `endConditionBinding()`.
    func beginConditionBinding(_ node: OptionalBindingConditionSyntax) {
        pendingConditionBindingsStack.append(resolvingConditionBinding(from: node))
    }

    func endConditionBinding() {
        if let local = pendingConditionBindingsStack.removeLast() {
            recordLocalBindingOrigin(local)
        }
    }

    private func recordingKnownLocalNames(
        from bindings: PatternBindingListSyntax
    ) -> [(name: String, origin: LocalBindingOrigin)] {
        let returnTypes = currentMethodReturnTypes
        let ambiguousMethodNames = currentAmbiguousReturnTypeMethodNames
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

    private func resolvingConditionBinding(
        from node: OptionalBindingConditionSyntax
    ) -> (name: String, origin: LocalBindingOrigin)? {
        if let name = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
            callSiteState.knownLocalNames.insert(name)
        }
        return callSites.localBinding(
            from: node, methodReturnTypes: currentMethodReturnTypes,
            ambiguousMethodNames: currentAmbiguousReturnTypeMethodNames)
    }

    /// Folds a resolved local-binding origin into `callSiteState`: a concrete type name into
    /// `localMap`, or a deferred `CallReceiver` into `localReceiverOriginMap` — the binding's later use
    /// as a receiver consults whichever one has an entry.
    private func recordLocalBindingOrigin(_ local: (name: String, origin: LocalBindingOrigin)) {
        switch local.origin {
        case .concrete(let type):
            callSiteState.localMap[local.name] = type
        case .deferred(let receiver):
            callSiteState.localReceiverOriginMap[local.name] = receiver
        }
    }

    // MARK: - Top-level (script-style) call collection

    /// Folds a top-level `let`/`var` binding's deferred origin (e.g. `let registry =
    /// ToolRegistry.standard`) into `topLevelGlobalReceiverOriginMap`, so a later `registry.method()`
    /// call in top-level code resolves.
    func recordTopLevelGlobalReceiverOrigins(from bindings: PatternBindingListSyntax) {
        for binding in bindings {
            guard let local = callSites.localBinding(from: binding), case .deferred(let receiver) = local.origin
            else { continue }
            topLevelGlobalReceiverOriginMap[local.name] = receiver
        }
    }

    // MARK: - Property-accessor / initializer call sites

    /// Call sites gathered from every accessor body of a type-level `var`/`let` declaration, so a
    /// method reached only from a computed property (a SwiftUI `body`, a derived value) is not
    /// mistaken for dead code.
    func accessorCallSites(
        from node: VariableDeclSyntax, propertyMap: [String: String], enclosingTypeName: String?, fileName: String
    ) -> [CallSite] {
        var sites: [CallSite] = []
        for binding in node.bindings {
            guard let accessor = binding.accessorBlock else { continue }
            let walker = propertyCallSiteWalker(
                propertyMap: propertyMap, enclosingTypeName: enclosingTypeName, fileName: fileName)
            walker.walk(accessor)
            sites.append(contentsOf: walker.collected)
        }
        return sites
    }

    /// Call sites made inside a stored property's initializer expression (`static let light =
    /// make(isDark: false)`) — the initializer-expression analogue of `accessorCallSites`, which only
    /// walks computed accessor bodies. Without this, a call made only from a stored property's
    /// initializer is invisible to the call graph.
    func initializerCallSites(
        from node: VariableDeclSyntax, propertyMap: [String: String], enclosingTypeName: String?, fileName: String
    ) -> [CallSite] {
        var sites: [CallSite] = []
        for binding in node.bindings {
            guard let value = binding.initializer?.value else { continue }
            let walker = propertyCallSiteWalker(
                propertyMap: propertyMap, enclosingTypeName: enclosingTypeName, fileName: fileName)
            walker.walk(value)
            sites.append(contentsOf: walker.collected)
        }
        return sites
    }

    private func propertyCallSiteWalker(
        propertyMap: [String: String], enclosingTypeName: String?, fileName: String
    ) -> AccessorCallSiteWalker {
        AccessorCallSiteWalker(
            collector: callSites, propertyMap: propertyMap, enclosingTypeName: enclosingTypeName,
            methodReturnTypes: currentMethodReturnTypes, methodNames: currentMethodNames, fileName: fileName)
    }

    // MARK: - Call-Site, Assignment & Field-Read Recording
    // The expression-shape interpretation lives in `CallSiteCollector`; this only stores what the
    // collector recovers.

    /// Resolves and records `node` as either a call site inside the current function body, or (when
    /// outside any function/type) a top-level script statement's call site.
    func recordCallSite(
        from node: FunctionCallExprSyntax, scope: CallSiteScope,
        enclosingTypeName: String?, topLevelGlobalPropertyMap: @autoclosure () -> [String: String], fileName: String
    ) {
        switch scope {
        case .functionBody:
            recordIterationClosureCallSites(in: node, enclosingTypeName: enclosingTypeName, fileName: fileName)
            // Parameters and locals resolve receivers too, but must not leak into field-read
            // detection, so they're merged in only here (shadowing same-named stored properties and
            // each other).
            var receiverMap = callSiteState.propertyMap
            if !callSiteState.parameterMap.isEmpty {
                receiverMap.merge(callSiteState.parameterMap) { _, parameter in parameter }
            }
            if !callSiteState.localMap.isEmpty {
                receiverMap.merge(callSiteState.localMap) { _, local in local }
            }
            if let site = callSites.callSite(
                from: node, propertyMap: receiverMap, enclosingTypeName: enclosingTypeName,
                knownLocalNames: callSiteState.knownLocalNames, fileName: fileName) ?? callSites.deferredCallSite(
                    from: node, localReceiverOriginMap: callSiteState.localReceiverOriginMap, fileName: fileName) {
                callSiteState.pendingCallSites.append(site)
            }
        case .fileScope:
            if let site = callSites.callSite(
                from: node, propertyMap: topLevelGlobalPropertyMap(), enclosingTypeName: nil, fileName: fileName)
                ?? callSites.deferredCallSite(
                    from: node, localReceiverOriginMap: topLevelGlobalReceiverOriginMap, fileName: fileName) {
                // A bare top-level statement: its calls have nowhere to attach as a member, so they're
                // recorded separately and given a synthetic reachable member in `buildArtifact()`.
                // Receivers resolve against globals declared earlier in the file (Swift's top-level
                // execution order guarantees a global's declaration precedes its use).
                topLevelCallSites.append(site)
            }
        case .other:
            break
        }
    }

    func recordAssignment(from node: SequenceExprSyntax, fileName: String) {
        guard let assignment = callSites.assignment(from: node, fileName: fileName) else { return }
        callSiteState.pendingAssignments.append(assignment)
    }

    func recordFieldReadAndMethodReference(from node: DeclReferenceExprSyntax, fileName: String) {
        if let read = callSites.fieldRead(from: node, propertyMap: callSiteState.propertyMap, fileName: fileName) {
            callSiteState.pendingFieldReads.append(read)
        }
        if callSites.isBareReferenceUse(node),
           let site = callSites.methodReference(
            from: node, propertyMap: callSiteState.propertyMap, methodNames: currentMethodNames, fileName: fileName) {
            callSiteState.pendingCallSites.append(site)
        }
    }

    /// Binds an implicit-`$0` iteration closure's parameter to the iterated array property's element
    /// type (`addedRelationships.map { $0.reportPhrase() }`) and records the resulting call sites. A
    /// no-op when `node` isn't such a closure or its receiver isn't a resolvable array property. The
    /// default child traversal still descends into the closure afterwards, redundantly but
    /// harmlessly — `$0` has no binding there, so nothing is double-counted.
    private func recordIterationClosureCallSites(
        in node: FunctionCallExprSyntax, enclosingTypeName: String?, fileName: String
    ) {
        guard let (receiverBase, closure) = callSites.iterationClosure(in: node),
              let elementReceiver = callSites.arrayElementReceiverType(
                of: receiverBase, arrayElementPropertyMap: callSiteState.arrayElementPropertyMap,
                enclosingTypeName: enclosingTypeName, knownLocalNames: callSiteState.knownLocalNames)
        else { return }
        let walker = Closure0CallSiteWalker(elementReceiver: elementReceiver, fileName: fileName)
        walker.walk(closure)
        callSiteState.pendingCallSites.append(contentsOf: walker.collected)
    }
}
