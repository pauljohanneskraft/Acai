import SwiftSyntax
import UMLCore

/// Per-function-body call-site-collection state: the property/parameter/local maps a call-site
/// receiver resolves against, and the buffers a body's calls/assignments/field-reads accumulate into
/// before being folded into its `Member`. Grouped into one value so resetting or clearing it — at the
/// start of a new top-of-body function/initializer, or once its member has been finalized — is a
/// single assignment instead of restating every field.
struct CallSiteAccumulator {
    var pendingCallSites: [CallSite] = []
    var pendingAssignments: [VariableAssignment] = []
    var pendingFieldReads: [FieldAccess] = []
    // Maps stored-property name → declared type name for the current type.
    var propertyMap: [String: String] = [:]
    // Maps stored-property name → declared *element* type name, for every array-typed (`[X]`)
    // property of the current type. Kept separate from `propertyMap` (which never resolves an
    // array-typed property at all): an array's element is only ever a valid receiver inside an
    // iteration closure's implicit `$0` (`CallSiteCollector.arrayElementReceiverType`), never for a
    // direct call on the property itself.
    var arrayElementPropertyMap: [String: String] = [:]
    // Maps local-variable name → provable declared type within the current body, so `local.method()`
    // resolves. Kept separate from `propertyMap`: locals are call-site receivers, not field reads.
    var localMap: [String: String] = [:]
    // Maps local/guard-let-variable name → a deferred `CallReceiver` descriptor, for a binding whose
    // type couldn't be proven *concretely* in this file (a cross-file same-type method return, a
    // `Type.staticMember` access) but is still resolvable post-merge. Consulted only after `localMap`
    // misses (`CallSiteCollector.deferredCallSite`), so a later `x.method()` still resolves.
    var localReceiverOriginMap: [String: CallReceiver] = [:]
    // Maps the current function/initializer's parameter name → declared type, so `param.method()`
    // resolves the same way a typed stored property does. Kept separate from `propertyMap` for the
    // same reason as `localMap`: a parameter is a call-site receiver, not a field.
    var parameterMap: [String: String] = [:]
    // Every local/parameter name declared so far in the current body, *whether or not* its type was
    // provable — unlike `localMap`/`parameterMap`, which only record the ones with a resolvable type.
    // Consulted so a local whose type inference failed (an ambiguous overload, a tuple return) isn't
    // mistaken for an unresolved own-property receiver (RC-multi-hop's `.ownProperty`): both look
    // identical — a lowercase name with no map entry — without this.
    var knownLocalNames: Set<String> = []
}

final class DeclarationVisitor: SyntaxVisitor {
    // Not `private`: read from `DeclarationVisitor+CallSiteHelpers.swift`'s extension, which lives in
    // a separate file (kept apart so this declaration stays within SwiftLint's `file_length`).
    let fileName: String
    var types: [TypeDeclaration] = []
    private var relationships: [Relationship] = []
    private var freestandingFunctions: [Member] = []
    var globalVariables: [Member] = []
    var typeStack: [TypeDeclaration] = []
    // Mirrors `typeStack`: each entry is the current type's `methodName → returnType` map (RC-I),
    // pre-passed from the raw syntax so a forward-declared method's return type is seen too.
    var methodReturnTypeMapStack: [[String: String]] = []
    // Mirrors `typeStack`: each entry is the set of this type's own method names with more than one
    // *distinct* return type among their overloads — absent from `methodReturnTypeMapStack` for the
    // same reason, but tracked separately so a genuinely ambiguous same-type overload (see
    // `ambiguousReturnTypeMethodNames`'s doc) is never mistaken for a cross-file method and deferred.
    var ambiguousReturnTypeMethodNamesStack: [Set<String>] = []
    // Mirrors `typeStack`: each entry is the current type's own method names, pre-passed the same way
    // as `methodReturnTypeMapStack` — lets a bare method-reference-as-value (`action: chooseFile`)
    // resolve regardless of whether the method is declared before or after the reference.
    var methodNameMapStack: [Set<String>] = []

    // MARK: - Call-site collection state
    // Tracks how many function/initializer bodies we are currently inside.
    // > 0 means we are walking a function body and should collect call sites
    // instead of treating nested declarations as new members.
    private var functionBodyDepth = 0
    var callSiteState = CallSiteAccumulator()
    // One entry per in-progress local `let`/`var` declaration, holding the bindings it will add to
    // `callSiteState.localMap` once its initializer has been fully visited (see `visitPost`) —
    // deferred so a self-referential initializer (`let size = size(for: id)`) still resolves against
    // the *outer* `size` method rather than the not-yet-in-scope local being declared.
    private var pendingLocalBindingsStack: [[(name: String, origin: LocalBindingOrigin)]] = []
    // One entry per in-progress `guard let`/`if let`/`while let` binding, mirroring
    // `pendingLocalBindingsStack`'s deferral: a shadowing initializer (`guard let self = self else {
    // return }`) must still resolve its RHS `self` against the *outer* scope, not the new local.
    private var pendingConditionBindingsStack: [(name: String, origin: LocalBindingOrigin)?] = []
    // Call sites made by bare top-level statements (a `main.swift`-style script), outside any
    // function or type body. Attached to a synthetic always-reachable freestanding member in
    // `buildArtifact()` so a callee reached only from top-level code isn't a dead-code false
    // positive (RC-H).
    private var topLevelCallSites: [CallSite] = []
    // The top-level analogue of `CallSiteAccumulator.localReceiverOriginMap`: a module-scope global's
    // deferred `CallReceiver` (a `Type.staticMember` initializer, e.g. `let registry =
    // ToolRegistry.standard`) whose type isn't provable as a *concrete* name but is still resolvable
    // post-merge. Consulted only after `topLevelGlobalPropertyMap()` misses.
    var topLevelGlobalReceiverOriginMap: [String: CallReceiver] = [:]
    // Simple names of every type declared in the file, seeded up front (in one pre-pass)
    // so `TypeName.method()` static calls resolve regardless of declaration order — including
    // forward-declared siblings — without misclassifying calls on unknown/external receivers.
    private let knownTypeNames: Set<String>
    // Each same-file protocol's requirement properties (`var x: T { get }`), keyed by protocol name
    // and seeded up front — a protocol extension's default implementation calling through one of
    // these (`history.undo()`) otherwise can't resolve, since the property lives on the protocol, not
    // the extension's own member list.
    let protocolProperties: [String: [String: String]]

    // Composable extractors: each owns one slice of the SwiftSyntax-to-model mapping, so this visitor
    // delegates rather than depending on every syntax node type directly.
    private let typeDeclarations = TypeDeclarationExtractor()
    private let members: MemberExtractor
    let signatures = DeclarationSignatureExtractor()
    let callSites: CallSiteCollector

    init(fileName: String, knownTypeNames: Set<String> = [], protocolProperties: [String: [String: String]] = [:]) {
        self.fileName = fileName
        self.knownTypeNames = knownTypeNames
        self.protocolProperties = protocolProperties
        self.members = MemberExtractor(knownTypeNames: knownTypeNames)
        self.callSites = CallSiteCollector(knownTypeNames: knownTypeNames)
        super.init(viewMode: .sourceAccurate)
    }

    func buildArtifact() -> CodeArtifact {
        var functions = freestandingFunctions
        if !topLevelCallSites.isEmpty {
            functions.append(Member(
                name: "<top-level>", kind: .method, accessLevel: .public, callSites: topLevelCallSites))
        }
        return CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: [fileName]),
            types: types,
            relationships: relationships,
            freestandingFunctions: functions,
            globalVariables: globalVariables
        )
    }

    // MARK: - Type Declarations

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0 else { return .skipChildren }
        let typeDecl = typeDeclarations.extractClass(from: node, fileName: fileName, namespace: currentNamespace)
        pushType(typeDecl, memberBlock: node.memberBlock)
        relationships.append(contentsOf: RelationshipExtractor().extract(from: node, typeId: typeDecl.id))
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        guard functionBodyDepth == 0 else { return }
        popType()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0 else { return .skipChildren }
        let typeDecl = typeDeclarations.extractStruct(from: node, fileName: fileName, namespace: currentNamespace)
        pushType(typeDecl, memberBlock: node.memberBlock)
        relationships.append(contentsOf: RelationshipExtractor().extract(from: node, typeId: typeDecl.id))
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        guard functionBodyDepth == 0 else { return }
        popType()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0 else { return .skipChildren }
        let typeDecl = typeDeclarations.extractEnum(from: node, fileName: fileName, namespace: currentNamespace)
        pushType(typeDecl, memberBlock: node.memberBlock)
        relationships.append(contentsOf: RelationshipExtractor().extract(from: node, typeId: typeDecl.id))
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        guard functionBodyDepth == 0 else { return }
        popType()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0 else { return .skipChildren }
        let typeDecl = typeDeclarations.extractProtocol(from: node, fileName: fileName, namespace: currentNamespace)
        pushType(typeDecl, memberBlock: node.memberBlock)
        relationships.append(contentsOf: RelationshipExtractor().extract(from: node, typeId: typeDecl.id))
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        guard functionBodyDepth == 0 else { return }
        // Protocol requirements can't carry their own access modifier — they inherit
        // the protocol's access level. Override the per-member default accordingly.
        let access = typeStack[typeStack.count - 1].accessLevel
        for index in typeStack[typeStack.count - 1].members.indices {
            typeStack[typeStack.count - 1].members[index].accessLevel = access
        }
        popType()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0 else { return .skipChildren }
        let typeDecl = typeDeclarations.extractExtension(from: node, fileName: fileName, namespace: currentNamespace)
        pushType(typeDecl, memberBlock: node.memberBlock)
        relationships.append(contentsOf: RelationshipExtractor().extract(from: node, typeId: typeDecl.id))
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        guard functionBodyDepth == 0 else { return }
        popType()
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0 else { return .skipChildren }
        let typeDecl = typeDeclarations.extractTypeAlias(from: node, fileName: fileName, namespace: currentNamespace)
        if typeStack.isEmpty {
            types.append(typeDecl)
        } else {
            typeStack[typeStack.count - 1].nestedTypes.append(typeDecl)
        }
        return .skipChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0 else { return .skipChildren }
        let typeDecl = typeDeclarations.extractActor(from: node, fileName: fileName, namespace: currentNamespace)
        pushType(typeDecl, memberBlock: node.memberBlock)
        relationships.append(contentsOf: RelationshipExtractor().extract(from: node, typeId: typeDecl.id))
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        guard functionBodyDepth == 0 else { return }
        popType()
    }

    // MARK: - Members

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Always balance the depth counter against `visitPost`, even for nested
        // functions — otherwise the counter underflows and every later declaration
        // in the file is silently dropped.
        let isNested = functionBodyDepth > 0
        functionBodyDepth += 1
        if isNested {
            // A local function declared inside another function's body isn't a member of its
            // own, but its calls are reachable the moment the enclosing function runs — so they
            // belong to the enclosing function's call sites, not a dead end. Descend and keep
            // accumulating into the same pending buffers (merging in its own parameters so
            // `param.method()` inside it still resolves).
            mergeNestedFunctionParameters(from: node.signature.parameterClause)
            return .visitChildren
        }

        // Capture the property map for this type before we descend.
        resetCallSiteState(parameterClause: node.signature.parameterClause)
        return .visitChildren   // descend so FunctionCallExprSyntax nodes are visited
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        functionBodyDepth -= 1
        // Only the top-of-body function becomes a member; nested ones contributed their call
        // sites to it above but aren't finalized here.
        guard functionBodyDepth == 0 else { return }
        var member = members.extractFunction(
            from: node, fileName: fileName, callSites: callSiteState.pendingCallSites,
            assignments: callSiteState.pendingAssignments, fieldReads: callSiteState.pendingFieldReads)
        if let body = node.body {
            member.referencedTypeNames = callSites.referencedTypes(in: body)
        }
        callSiteState = CallSiteAccumulator()
        if typeStack.isEmpty {
            freestandingFunctions.append(member)
        } else {
            typeStack[typeStack.count - 1].members.append(member)
        }
    }

    override func visit(_ node: OptionalBindingConditionSyntax) -> SyntaxVisitorContinueKind {
        // `guard let x = …` / `if let x = …` — the condition-list analogue of a local `VariableDeclSyntax`.
        // Same deferral as below: resolve+merge the type only after the initializer has been fully
        // visited (see `resolvingConditionBinding`), so a shadowing initializer (`guard let self = self
        // else { return }`) still resolves its RHS against the outer scope.
        guard functionBodyDepth > 0 else { return .visitChildren }
        pendingConditionBindingsStack.append(resolvingConditionBinding(from: node))
        return .visitChildren
    }

    override func visitPost(_ node: OptionalBindingConditionSyntax) {
        guard functionBodyDepth > 0 else { return }
        if let local = pendingConditionBindingsStack.removeLast() {
            recordLocalBindingOrigin(local)
        }
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Local variables inside a function body aren't members, but recording their provable type
        // lets a later `local.method()` call resolve. Descend into the initializer too, so a call in
        // `let x = obj.compute()` is collected rather than lost with the declaration.
        guard functionBodyDepth == 0 else {
            // Bindings aren't added to `callSiteState.localMap` until `visitPost` (see its doc) — this
            // only records their *names* immediately, and defers their resolved types.
            pendingLocalBindingsStack.append(recordingKnownLocalNames(from: node.bindings))
            return .visitChildren
        }
        var extractedMembers = attachingInitializerReferencedTypes(
            to: members.extractVariable(from: node, fileName: fileName), from: node)
        // Collect call sites made inside computed-property accessor bodies (e.g. a SwiftUI `var body`
        // that calls helper methods) and stored-property initializer expressions (`static let light =
        // make(isDark: false)`), so a callee reached only through a property isn't seen as dead. A
        // binding is either stored or computed, never both, so unconditional attachment is safe —
        // `collectAccessorCallSites` is always empty for a stored binding (no accessor block) and
        // `collectInitializerCallSites` is always empty for a computed one (no initializer).
        let propertySites = collectAccessorCallSites(from: node) + collectInitializerCallSites(from: node)
        if !propertySites.isEmpty {
            extractedMembers = extractedMembers.map { member in
                var copy = member
                copy.callSites = propertySites
                return copy
            }
        }
        if typeStack.isEmpty {
            // Top-level (module-scope) `let`/`var`.
            recordingTopLevelGlobalReceiverOrigins(from: node.bindings)
            globalVariables.append(contentsOf: extractedMembers)
        } else {
            typeStack[typeStack.count - 1].members.append(contentsOf: extractedMembers)
        }
        return .skipChildren
    }

    // Only now — after the binding's initializer has been fully visited — are its resolved-type
    // bindings folded into `callSiteState.localMap`. Swift scoping doesn't put a name in scope until
    // after its own initializer finishes evaluating, so `let size = size(for: id)` must still resolve
    // the RHS call against the *outer* `size` method rather than the local being declared.
    override func visitPost(_ node: VariableDeclSyntax) {
        guard functionBodyDepth == 0 else {
            for local in pendingLocalBindingsStack.removeLast() {
                recordLocalBindingOrigin(local)
            }
            return
        }
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        // Balance the depth counter against `visitPost` unconditionally (see the
        // function-decl note above).
        let isNested = functionBodyDepth > 0
        functionBodyDepth += 1
        guard !isNested, !typeStack.isEmpty else { return .skipChildren }
        resetCallSiteState(parameterClause: node.signature.parameterClause)
        return .visitChildren
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        functionBodyDepth -= 1
        guard functionBodyDepth == 0, !typeStack.isEmpty else { return }
        var member = members.extractInitializer(
            from: node, fileName: fileName, callSites: callSiteState.pendingCallSites,
            assignments: callSiteState.pendingAssignments, fieldReads: callSiteState.pendingFieldReads)
        if let body = node.body {
            member.referencedTypeNames = callSites.referencedTypes(in: body)
        }
        callSiteState = CallSiteAccumulator()
        typeStack[typeStack.count - 1].members.append(member)
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0, !typeStack.isEmpty else { return .skipChildren }
        let member = members.extractDeinitializer(from: node, fileName: fileName)
        typeStack[typeStack.count - 1].members.append(member)
        return .skipChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0, !typeStack.isEmpty else { return .skipChildren }
        let member = members.extractSubscript(from: node, fileName: fileName)
        typeStack[typeStack.count - 1].members.append(member)
        return .skipChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0, !typeStack.isEmpty else { return .skipChildren }
        let cases = members.extractEnumCases(from: node, fileName: fileName)
        typeStack[typeStack.count - 1].enumCases.append(contentsOf: cases)
        return .skipChildren
    }

    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0, !typeStack.isEmpty else { return .skipChildren }
        typeStack[typeStack.count - 1].associatedTypes.append(
            signatures.extractAssociatedType(from: node))
        return .skipChildren
    }

    // MARK: - Conditional Compilation

    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        // Walk only the first clause to avoid double-counting declarations that
        // appear in multiple #if/#else branches. Without build settings we can't
        // know which branch is active; the first (#if) is the closest approximation.
        if let firstClause = node.clauses.first {
            walk(firstClause)
        }
        return .skipChildren
    }

    // MARK: - Call-Site & Assignment Collection
    // The expression-shape interpretation lives in `CallSiteCollector`; this visitor only drives the
    // walk and stores what the collector recovers.

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Parameters and locals resolve receivers too, but they must not leak into field-read
        // detection, so they're merged in only here (parameters, then locals, shadowing same-named
        // stored properties — and each other, in declaration order).
        var receiverMap = callSiteState.propertyMap
        if !callSiteState.parameterMap.isEmpty {
            receiverMap.merge(callSiteState.parameterMap) { _, parameter in parameter }
        }
        if !callSiteState.localMap.isEmpty {
            receiverMap.merge(callSiteState.localMap) { _, local in local }
        }
        // An implicit-`$0` iteration closure (`addedRelationships.map { $0.reportPhrase() }`) — see
        // `recordingIterationClosureCallSites`'s doc. The default child traversal below still descends
        // into the closure afterwards, redundantly but harmlessly (see that doc for why).
        if functionBodyDepth > 0 {
            recordingIterationClosureCallSites(in: node)
        }
        if functionBodyDepth > 0,
           let site = callSites.callSite(
               from: node, propertyMap: receiverMap,
               enclosingTypeName: typeStack.last?.name, knownLocalNames: callSiteState.knownLocalNames,
               fileName: fileName) ?? callSites.deferredCallSite(
                from: node, localReceiverOriginMap: callSiteState.localReceiverOriginMap, fileName: fileName) {
            callSiteState.pendingCallSites.append(site)
        } else if functionBodyDepth == 0, typeStack.isEmpty,
                  let site = callSites.callSite(
                    from: node, propertyMap: topLevelGlobalPropertyMap(),
                    enclosingTypeName: nil, fileName: fileName) ?? callSites.deferredCallSite(
                        from: node, localReceiverOriginMap: topLevelGlobalReceiverOriginMap, fileName: fileName) {
            // A bare top-level statement (a `main.swift`-style script): its calls have nowhere to
            // attach as a member, so they're recorded separately and given a synthetic reachable
            // member in `buildArtifact()` (RC-H). Receivers resolve against `globalVariables`
            // declared earlier in the file (Swift's top-level execution order guarantees a global's
            // declaration precedes its use), the top-level analogue of `callSiteState.propertyMap`.
            topLevelCallSites.append(site)
        }
        return .visitChildren
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        if functionBodyDepth > 0,
           let assignment = callSites.assignment(from: node, fileName: fileName) {
            callSiteState.pendingAssignments.append(assignment)
        }
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        // A bare identifier or the member of a `self.x` access — recorded when it names a stored
        // property of the enclosing type (issue #111). Filtering to `callSiteState.propertyMap` keeps
        // this to own-field reads; consumers tolerate the same-name-local ambiguity as for assignments.
        if functionBodyDepth > 0,
           let read = callSites.fieldRead(
               from: node, propertyMap: callSiteState.propertyMap, fileName: fileName) {
            callSiteState.pendingFieldReads.append(read)
        }
        // A bare method name used as a value (`action: chooseFile`), not a call — see
        // `CallSiteCollector.isBareReferenceUse`'s doc for why a real call's callee and a qualified
        // `object.method` access are excluded here.
        if functionBodyDepth > 0, callSites.isBareReferenceUse(node),
           let site = callSites.methodReference(
               from: node, propertyMap: callSiteState.propertyMap, methodNames: methodNameMapStack.last ?? [],
               fileName: fileName) {
            callSiteState.pendingCallSites.append(site)
        }
        return .visitChildren
    }

}
