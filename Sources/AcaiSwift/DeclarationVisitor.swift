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

final class DeclarationVisitor: SyntaxVisitor {
    // Not `private`: read from `DeclarationVisitor+CallSiteHelpers.swift`'s extension (split out to
    // stay within SwiftLint's `file_length`).
    let fileName: String
    var types: [TypeDeclaration] = []
    private var relationships: [Relationship] = []
    private var freestandingFunctions: [Member] = []
    var globalVariables: [Member] = []
    var typeStack: [TypeDeclaration] = []
    /// Mirrors `typeStack`: each entry is the current type's `methodName → returnType` map, pre-passed
    /// from the raw syntax so a forward-declared method's return type is seen too.
    var methodReturnTypeMapStack: [[String: String]] = []
    /// Mirrors `typeStack`: each entry is this type's own method names with more than one distinct
    /// return type among overloads — tracked separately so a genuinely ambiguous overload is never
    /// mistaken for a cross-file method and deferred.
    var ambiguousReturnTypeMethodNamesStack: [Set<String>] = []
    /// Mirrors `typeStack`: each entry is the current type's own method names, pre-passed so a bare
    /// method-reference-as-value (`action: chooseFile`) resolves regardless of declaration order.
    var methodNameMapStack: [Set<String>] = []

    // MARK: - Call-site collection state

    /// How many function/initializer bodies we're currently inside. > 0 means collect call sites
    /// instead of treating nested declarations as new members.
    private var functionBodyDepth = 0
    var callSiteState = CallSiteAccumulator()
    /// One entry per in-progress local `let`/`var`, holding bindings to add to `callSiteState.localMap`
    /// once its initializer is fully visited — deferred so a self-referential initializer (`let size =
    /// size(for: id)`) resolves against the outer `size` method, not the not-yet-in-scope local.
    private var pendingLocalBindingsStack: [[(name: String, origin: LocalBindingOrigin)]] = []
    /// One entry per in-progress `guard let`/`if let`/`while let` binding, same deferral as
    /// `pendingLocalBindingsStack`: a shadowing initializer (`guard let self = self else { return }`)
    /// must resolve its RHS `self` against the outer scope, not the new local.
    private var pendingConditionBindingsStack: [(name: String, origin: LocalBindingOrigin)?] = []
    /// Call sites from bare top-level statements (a `main.swift`-style script), outside any function
    /// or type body. Attached to a synthetic always-reachable member in `buildArtifact()` so a callee
    /// reached only from top-level code isn't a dead-code false positive.
    private var topLevelCallSites: [CallSite] = []
    /// The top-level analogue of `CallSiteAccumulator.localReceiverOriginMap`: a module-scope global's
    /// deferred `CallReceiver` whose type isn't provable concretely but is resolvable post-merge.
    /// Consulted only after `topLevelGlobalPropertyMap()` misses.
    var topLevelGlobalReceiverOriginMap: [String: CallReceiver] = [:]
    /// Simple names of every type declared in the file, seeded up front so `TypeName.method()` static
    /// calls resolve regardless of declaration order, including forward-declared siblings.
    private let knownTypeNames: Set<String>
    /// Each same-file protocol's requirement properties (`var x: T { get }`), keyed by protocol name —
    /// a protocol extension's default implementation calling through one of these otherwise can't
    /// resolve, since the property lives on the protocol, not the extension's own member list.
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
        // Protocol requirements inherit the protocol's access level, not their own modifier.
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
        // Balance the depth counter against `visitPost` even for nested functions, or the counter
        // underflows and every later declaration is silently dropped.
        let isNested = functionBodyDepth > 0
        functionBodyDepth += 1
        if isNested {
            // A local function isn't a member of its own, but its calls are reachable once the
            // enclosing function runs — so descend and keep accumulating into the same pending
            // buffers (merging in its own parameters so `param.method()` inside it resolves).
            mergeNestedFunctionParameters(from: node.signature.parameterClause)
            return .visitChildren
        }
        resetCallSiteState(parameterClause: node.signature.parameterClause)
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        functionBodyDepth -= 1
        // Only the top-of-body function becomes a member; nested ones already contributed above.
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
        // `guard let x = …` / `if let x = …`: the condition-list analogue of a local VariableDeclSyntax.
        // Same deferral as below, so a shadowing initializer resolves its RHS against the outer scope.
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
        // Local variables aren't members, but recording their provable type lets a later
        // `local.method()` resolve. Descend into the initializer too, so a call in `let x =
        // obj.compute()` is collected.
        guard functionBodyDepth == 0 else {
            // Bindings aren't added to `callSiteState.localMap` until `visitPost` — this only records
            // names immediately and defers resolved types.
            pendingLocalBindingsStack.append(recordingKnownLocalNames(from: node.bindings))
            return .visitChildren
        }
        var extractedMembers = attachingInitializerReferencedTypes(
            to: members.extractVariable(from: node, fileName: fileName), from: node)
        // Collect call sites from computed-property accessor bodies and stored-property initializer
        // expressions, so a callee reached only through a property isn't seen as dead. A binding is
        // either stored or computed, never both, so unconditional attachment is safe.
        let propertySites = collectAccessorCallSites(from: node) + collectInitializerCallSites(from: node)
        if !propertySites.isEmpty {
            extractedMembers = extractedMembers.map { member in
                var copy = member
                copy.callSites = propertySites
                return copy
            }
        }
        if typeStack.isEmpty {
            // Top-level (module-scope) let/var.
            recordingTopLevelGlobalReceiverOrigins(from: node.bindings)
            globalVariables.append(contentsOf: extractedMembers)
        } else {
            typeStack[typeStack.count - 1].members.append(contentsOf: extractedMembers)
        }
        return .skipChildren
    }

    // Only after the initializer is fully visited are its resolved-type bindings folded into
    // `callSiteState.localMap` — Swift scoping doesn't put a name in scope until its own initializer
    // finishes, so `let size = size(for: id)` must resolve the RHS against the outer `size` method.
    override func visitPost(_ node: VariableDeclSyntax) {
        guard functionBodyDepth == 0 else {
            for local in pendingLocalBindingsStack.removeLast() {
                recordLocalBindingOrigin(local)
            }
            return
        }
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        // Balance the depth counter against `visitPost` unconditionally (see the function-decl note above).
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
        // Walk only the first clause to avoid double-counting declarations across #if/#else branches;
        // without build settings, the first (#if) is the closest approximation of the active one.
        if let firstClause = node.clauses.first {
            walk(firstClause)
        }
        return .skipChildren
    }

    // MARK: - Call-Site & Assignment Collection
    // The expression-shape interpretation lives in `CallSiteCollector`; this visitor only drives the
    // walk and stores what the collector recovers.

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Parameters and locals resolve receivers too, but must not leak into field-read detection,
        // so they're merged in only here (shadowing same-named stored properties and each other).
        var receiverMap = callSiteState.propertyMap
        if !callSiteState.parameterMap.isEmpty {
            receiverMap.merge(callSiteState.parameterMap) { _, parameter in parameter }
        }
        if !callSiteState.localMap.isEmpty {
            receiverMap.merge(callSiteState.localMap) { _, local in local }
        }
        // An implicit-`$0` iteration closure (see `recordingIterationClosureCallSites`'s doc). The
        // default child traversal below still descends into the closure too, redundantly but harmlessly.
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
            // A bare top-level statement: its calls have nowhere to attach as a member, so they're
            // recorded separately and given a synthetic reachable member in `buildArtifact()`.
            // Receivers resolve against `globalVariables` declared earlier in the file (Swift's
            // top-level execution order guarantees a global's declaration precedes its use).
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
        // A bare identifier or the member of a `self.x` access, recorded when it names a stored
        // property of the enclosing type (issue #111).
        if functionBodyDepth > 0,
           let read = callSites.fieldRead(
               from: node, propertyMap: callSiteState.propertyMap, fileName: fileName) {
            callSiteState.pendingFieldReads.append(read)
        }
        // A bare method name used as a value (`action: chooseFile`), not a call — see
        // `CallSiteCollector.isBareReferenceUse`'s doc for the exclusions.
        if functionBodyDepth > 0, callSites.isBareReferenceUse(node),
           let site = callSites.methodReference(
               from: node, propertyMap: callSiteState.propertyMap, methodNames: methodNameMapStack.last ?? [],
               fileName: fileName) {
            callSiteState.pendingCallSites.append(site)
        }
        return .visitChildren
    }

}
