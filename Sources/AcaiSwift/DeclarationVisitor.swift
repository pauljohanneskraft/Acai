import SwiftSyntax
import AcaiCore

final class DeclarationVisitor: SyntaxVisitor {
    let fileName: String
    var types: [TypeDeclaration] = []
    private var relationships: [Relationship] = []
    private var freestandingFunctions: [Member] = []
    var globalVariables: [Member] = []
    var typeStack: [TypeDeclaration] = []

    /// How many function/initializer bodies we're currently inside. > 0 means collect call sites
    /// instead of treating nested declarations as new members.
    private var functionBodyDepth = 0
    /// Simple names of every type declared in the file, seeded up front so `TypeName.method()` static
    /// calls resolve regardless of declaration order, including forward-declared siblings.
    private let knownTypeNames: Set<String>
    /// Each same-file protocol's requirement properties (`var x: T { get }`), keyed by protocol name —
    /// a protocol extension's default implementation calling through one of these otherwise can't
    /// resolve, since the property lives on the protocol, not the extension's own member list.
    let protocolProperties: [String: [String: String]]

    private let typeDeclarations = TypeDeclarationExtractor()
    private let members: MemberExtractor
    let signatures = DeclarationSignatureExtractor()
    /// Owns the call-site/assignment/field-read collection concern: the per-function-body accumulator,
    /// deferred local bindings, top-level call collection, and the per-type lookups their resolution
    /// needs. `DeclarationVisitor` drives the walk and supplies type/member context at the seams below
    /// (`pushType`/`popType`, the function/initializer visitors); the bookkeeping itself lives there.
    let scope: CallSiteTracker

    init(fileName: String, knownTypeNames: Set<String> = [], protocolProperties: [String: [String: String]] = [:]) {
        self.fileName = fileName
        self.knownTypeNames = knownTypeNames
        self.protocolProperties = protocolProperties
        self.members = MemberExtractor(knownTypeNames: knownTypeNames)
        self.scope = CallSiteTracker(knownTypeNames: knownTypeNames)
        super.init(viewMode: .sourceAccurate)
    }

    func buildArtifact() -> CodeArtifact {
        var functions = freestandingFunctions
        if !scope.topLevelCallSites.isEmpty {
            functions.append(Member(
                name: "<top-level>", kind: .method, accessLevel: .public, callSites: scope.topLevelCallSites))
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
            scope.mergeNestedFunctionParameters(from: node.signature.parameterClause)
            return .visitChildren
        }
        scope.resetCallSiteState(
            propertyMap: buildPropertyMap(), arrayElementPropertyMap: buildArrayElementPropertyMap(),
            parameterClause: node.signature.parameterClause)
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        functionBodyDepth -= 1
        // Only the top-of-body function becomes a member; nested ones already contributed above.
        guard functionBodyDepth == 0 else { return }
        var member = members.extractFunction(
            from: node, fileName: fileName, callSites: scope.callSiteState.pendingCallSites,
            assignments: scope.callSiteState.pendingAssignments, fieldReads: scope.callSiteState.pendingFieldReads)
        if let body = node.body {
            member.referencedTypeNames = scope.callSites.referencedTypes(in: body)
        }
        scope.clearCallSiteState()
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
        scope.beginConditionBinding(node)
        return .visitChildren
    }

    override func visitPost(_ node: OptionalBindingConditionSyntax) {
        guard functionBodyDepth > 0 else { return }
        scope.endConditionBinding()
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Local variables aren't members, but recording their provable type lets a later
        // `local.method()` resolve. Descend into the initializer too, so a call in `let x =
        // obj.compute()` is collected.
        guard functionBodyDepth == 0 else {
            // Bindings aren't added to the local map until `visitPost` — this only records names
            // immediately and defers resolved types.
            scope.beginLocalBindings(node.bindings)
            return .visitChildren
        }
        var extractedMembers = attachingInitializerReferencedTypes(
            to: members.extractVariable(from: node, fileName: fileName), from: node)
        // Collect call sites from computed-property accessor bodies and stored-property initializer
        // expressions, so a callee reached only through a property isn't seen as dead. A binding is
        // either stored or computed, never both, so unconditional attachment is safe.
        let propertySites = collectPropertyCallSites(from: node)
        if !propertySites.isEmpty {
            extractedMembers = extractedMembers.map { member in
                var copy = member
                copy.callSites = propertySites
                return copy
            }
        }
        if typeStack.isEmpty {
            scope.recordTopLevelGlobalReceiverOrigins(from: node.bindings)
            globalVariables.append(contentsOf: extractedMembers)
        } else {
            typeStack[typeStack.count - 1].members.append(contentsOf: extractedMembers)
        }
        return .skipChildren
    }

    // Only after the initializer is fully visited are its resolved-type bindings folded into the
    // deferred-binding maps — Swift scoping doesn't put a name in scope until its own initializer
    // finishes, so `let size = size(for: id)` must resolve the RHS against the outer `size` method.
    override func visitPost(_ node: VariableDeclSyntax) {
        guard functionBodyDepth == 0 else {
            scope.endLocalBindings()
            return
        }
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        // Balance the depth counter against `visitPost` unconditionally (see the function-decl note above).
        let isNested = functionBodyDepth > 0
        functionBodyDepth += 1
        guard !isNested, !typeStack.isEmpty else { return .skipChildren }
        scope.resetCallSiteState(
            propertyMap: buildPropertyMap(), arrayElementPropertyMap: buildArrayElementPropertyMap(),
            parameterClause: node.signature.parameterClause)
        return .visitChildren
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        functionBodyDepth -= 1
        guard functionBodyDepth == 0, !typeStack.isEmpty else { return }
        var member = members.extractInitializer(
            from: node, fileName: fileName, callSites: scope.callSiteState.pendingCallSites,
            assignments: scope.callSiteState.pendingAssignments, fieldReads: scope.callSiteState.pendingFieldReads)
        if let body = node.body {
            member.referencedTypeNames = scope.callSites.referencedTypes(in: body)
        }
        scope.clearCallSiteState()
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
    // The expression-shape interpretation lives in `CallSiteCollector`; state and bookkeeping live in
    // `CallSiteTracker` (`scope`); this visitor only drives the walk and supplies type context.

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        scope.recordCallSite(
            from: node, scope: functionBodyDepth > 0 ? .functionBody : (typeStack.isEmpty ? .fileScope : .other),
            enclosingTypeName: typeStack.last?.name, topLevelGlobalPropertyMap: topLevelGlobalPropertyMap(),
            fileName: fileName)
        return .visitChildren
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        if functionBodyDepth > 0 {
            scope.recordAssignment(from: node, fileName: fileName)
        }
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        if functionBodyDepth > 0 {
            scope.recordFieldReadAndMethodReference(from: node, fileName: fileName)
        }
        return .visitChildren
    }

}
