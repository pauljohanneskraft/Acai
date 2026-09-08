import SwiftSyntax
import AcaiCore

struct CallSiteAccumulator {
    var pendingCallSites: [CallSite] = []
    var pendingAssignments: [VariableAssignment] = []
    var pendingFieldReads: [FieldAccess] = []
    var propertyMap: [String: String] = [:]
    /// Separate from `propertyMap`: an array's element is only a valid receiver inside an iteration
    /// closure's implicit `$0`, never a direct call on the property itself.
    var arrayElementPropertyMap: [String: String] = [:]
    var localMap: [String: String] = [:]
    /// A binding whose type couldn't be proven concretely in this file but is resolvable post-merge.
    /// Consulted only after `localMap` misses.
    var localReceiverOriginMap: [String: CallReceiver] = [:]
    var parameterMap: [String: String] = [:]
    /// Every local/parameter name declared so far, whether or not its type was provable — unlike
    /// `localMap`/`parameterMap`. Consulted so a local whose type inference failed isn't mistaken for
    /// an unresolved own-property receiver: both look identical (a lowercase name, no map entry).
    var knownLocalNames: Set<String> = []
}

/// Where a `FunctionCallExprSyntax` was found: inside a function/closure body, at bare top-level
/// script scope, or neither (e.g. a default parameter value) — a call `recordCallSite` attaches
/// nowhere.
enum CallSiteScope {
    case functionBody
    case fileScope
    case other
}

/// Owns everything `DeclarationVisitor` needs to collect call sites, assignments and field reads
/// while it walks a file. Expression-shape interpretation stays in `CallSiteCollector` (held here,
/// stateless); this is the traversal-state counterpart the visitor drives through push/pop and
/// begin/end calls, supplying the type/member context it doesn't own itself.
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

    /// Built from a raw pre-pass over the type's direct member list, so a forward-declared method's
    /// return type is seen regardless of source order. Keeps only names with a single, unambiguous
    /// return type across overloads.
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

    private func methodNames(from memberBlock: MemberBlockSyntax) -> Set<String> {
        Set(memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self)?.name.text })
    }

    // MARK: - Function-body state

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

    func clearCallSiteState() {
        callSiteState = CallSiteAccumulator()
    }

    private func parameterMap(from parameterClause: FunctionParameterClauseSyntax) -> [String: String] {
        var map: [String: String] = [:]
        for parameter in signatures.extractParameters(from: parameterClause) {
            if let typeName = parameter.type?.name {
                map[parameter.internalName] = typeName
            }
        }
        return map
    }

    private func knownParameterNames(from parameterClause: FunctionParameterClauseSyntax) -> Set<String> {
        Set(signatures.extractParameters(from: parameterClause).map(\.internalName))
    }

    func mergeNestedFunctionParameters(from parameterClause: FunctionParameterClauseSyntax) {
        for parameter in signatures.extractParameters(from: parameterClause) {
            callSiteState.knownLocalNames.insert(parameter.internalName)
            if let typeName = parameter.type?.name {
                callSiteState.parameterMap[parameter.internalName] = typeName
            }
        }
    }

    // MARK: - Local & condition bindings

    /// Records every binding's name into `knownLocalNames` immediately, and defers the bindings whose
    /// origin could also be resolved until `endLocalBindings()`, once their initializer has been fully
    /// visited: Swift scoping doesn't put a name in scope until its own initializer finishes, so `let
    /// size = size(for: id)` must resolve the RHS against the outer `size` method, not the
    /// not-yet-in-scope local.
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

    private func recordLocalBindingOrigin(_ local: (name: String, origin: LocalBindingOrigin)) {
        switch local.origin {
        case .concrete(let type):
            callSiteState.localMap[local.name] = type
        case .deferred(let receiver):
            callSiteState.localReceiverOriginMap[local.name] = receiver
        }
    }

    // MARK: - Top-level (script-style) call collection

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

    /// The initializer-expression analogue of `accessorCallSites` (`static let light = make(isDark:
    /// false)`), which only walks computed accessor bodies. Without this, a call made only from a
    /// stored property's initializer is invisible to the call graph.
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
                // Its calls have nowhere to attach as a member, so they're recorded separately and
                // given a synthetic reachable member in `buildArtifact()`.
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
    /// type (`addedRelationships.map { $0.reportPhrase() }`). A no-op when `node` isn't such a closure
    /// or its receiver isn't a resolvable array property.
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
