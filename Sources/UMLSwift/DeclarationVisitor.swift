import SwiftSyntax
import UMLCore

final class DeclarationVisitor: SyntaxVisitor {
    private let fileName: String
    private var types: [TypeDeclaration] = []
    private var relationships: [Relationship] = []
    private var freestandingFunctions: [Member] = []
    private var globalVariables: [Member] = []
    private var typeStack: [TypeDeclaration] = []

    // MARK: - Call-site collection state
    // Tracks how many function/initializer bodies we are currently inside.
    // > 0 means we are walking a function body and should collect call sites
    // instead of treating nested declarations as new members.
    private var functionBodyDepth = 0
    private var pendingCallSites: [CallSite] = []
    private var pendingAssignments: [VariableAssignment] = []
    private var pendingFieldReads: [FieldAccess] = []
    // Maps stored-property name → declared type name for the current type.
    private var callSitePropertyMap: [String: String] = [:]
    // Maps local-variable name → provable declared type within the current body, so `local.method()`
    // resolves. Kept separate from the property map: locals are call-site receivers, not field reads.
    private var callSiteLocalMap: [String: String] = [:]
    // Simple names of every type declared in the file, seeded up front (in one pre-pass)
    // so `TypeName.method()` static calls resolve regardless of declaration order — including
    // forward-declared siblings — without misclassifying calls on unknown/external receivers.
    private let knownTypeNames: Set<String>

    // Composable extractors: each owns one slice of the SwiftSyntax-to-model mapping, so this visitor
    // delegates rather than depending on every syntax node type directly.
    private let typeDeclarations = TypeDeclarationExtractor()
    private let members: MemberExtractor
    private let signatures = DeclarationSignatureExtractor()
    private let callSites: CallSiteCollector

    init(fileName: String, knownTypeNames: Set<String> = []) {
        self.fileName = fileName
        self.knownTypeNames = knownTypeNames
        self.members = MemberExtractor(knownTypeNames: knownTypeNames)
        self.callSites = CallSiteCollector(knownTypeNames: knownTypeNames)
        super.init(viewMode: .sourceAccurate)
    }

    func buildArtifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: [fileName]),
            types: types,
            relationships: relationships,
            freestandingFunctions: freestandingFunctions,
            globalVariables: globalVariables
        )
    }

    // MARK: - Type Declarations

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0 else { return .skipChildren }
        let typeDecl = typeDeclarations.extractClass(from: node, fileName: fileName, namespace: currentNamespace)
        pushType(typeDecl)
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
        pushType(typeDecl)
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
        pushType(typeDecl)
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
        pushType(typeDecl)
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
        pushType(typeDecl)
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
        pushType(typeDecl)
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
        // functions we don't descend into — otherwise the counter underflows and
        // every later declaration in the file is silently dropped.
        let isNested = functionBodyDepth > 0
        functionBodyDepth += 1
        // Inside another function body: skip the nested function entirely.
        guard !isNested else { return .skipChildren }

        // Capture the property map for this type before we descend.
        callSitePropertyMap = buildPropertyMap()
        callSiteLocalMap = [:]
        pendingCallSites = []
        pendingAssignments = []
        pendingFieldReads = []
        return .visitChildren   // descend so FunctionCallExprSyntax nodes are visited
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        functionBodyDepth -= 1
        // Only the top-of-body function becomes a member; nested ones are skipped.
        guard functionBodyDepth == 0 else { return }
        var member = members.extractFunction(
            from: node, fileName: fileName, callSites: pendingCallSites,
            assignments: pendingAssignments, fieldReads: pendingFieldReads)
        if let body = node.body {
            member.referencedTypeNames = callSites.referencedTypes(in: body)
        }
        pendingCallSites = []
        pendingAssignments = []
        pendingFieldReads = []
        callSitePropertyMap = [:]
        if typeStack.isEmpty {
            freestandingFunctions.append(member)
        } else {
            typeStack[typeStack.count - 1].members.append(member)
        }
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Local variables inside a function body aren't members, but recording their provable type
        // lets a later `local.method()` call resolve. Descend into the initializer too, so a call in
        // `let x = obj.compute()` is collected rather than lost with the declaration.
        guard functionBodyDepth == 0 else {
            for binding in node.bindings {
                if let local = callSites.localBinding(from: binding) {
                    callSiteLocalMap[local.name] = local.type
                }
            }
            return .visitChildren
        }
        var extractedMembers = members.extractVariable(from: node, fileName: fileName)
        // Capture type references in the property's *initializer* only (e.g. `= Foo()`), which the
        // signature misses — surfaces construction dependencies for the coupling metrics. Deliberately
        // skips accessor bodies (computed getters): walking a deeply nested `var body: some View { … }`
        // would recurse far enough to overflow the stack.
        var referencedSet = Set<String>()
        for binding in node.bindings {
            if let value = binding.initializer?.value {
                referencedSet.formUnion(callSites.referencedTypes(in: value))
            }
        }
        let referenced = Array(referencedSet)
        if !referenced.isEmpty {
            extractedMembers = extractedMembers.map { member in
                var copy = member
                copy.referencedTypeNames = referenced
                return copy
            }
        }
        // Collect call sites made inside computed-property accessor bodies (e.g. a SwiftUI `var body`
        // that calls helper methods), so callees reached only through a property aren't seen as dead.
        let accessorSites = collectAccessorCallSites(from: node)
        if !accessorSites.isEmpty {
            extractedMembers = extractedMembers.map { member in
                guard member.isComputed else { return member }
                var copy = member
                copy.callSites = accessorSites
                return copy
            }
        }
        if typeStack.isEmpty {
            // Top-level (module-scope) `let`/`var`.
            globalVariables.append(contentsOf: extractedMembers)
        } else {
            typeStack[typeStack.count - 1].members.append(contentsOf: extractedMembers)
        }
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        // Balance the depth counter against `visitPost` unconditionally (see the
        // function-decl note above).
        let isNested = functionBodyDepth > 0
        functionBodyDepth += 1
        guard !isNested, !typeStack.isEmpty else { return .skipChildren }
        callSitePropertyMap = buildPropertyMap()
        callSiteLocalMap = [:]
        pendingCallSites = []
        pendingAssignments = []
        pendingFieldReads = []
        return .visitChildren
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        functionBodyDepth -= 1
        guard functionBodyDepth == 0, !typeStack.isEmpty else { return }
        var member = members.extractInitializer(
            from: node, fileName: fileName, callSites: pendingCallSites,
            assignments: pendingAssignments, fieldReads: pendingFieldReads)
        if let body = node.body {
            member.referencedTypeNames = callSites.referencedTypes(in: body)
        }
        pendingCallSites = []
        pendingAssignments = []
        pendingFieldReads = []
        callSitePropertyMap = [:]
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
        // Locals resolve receivers too, but they must not leak into field-read detection, so they're
        // merged in only here (with locals shadowing same-named stored properties).
        let receiverMap = callSiteLocalMap.isEmpty
            ? callSitePropertyMap
            : callSitePropertyMap.merging(callSiteLocalMap) { _, local in local }
        if functionBodyDepth > 0,
           let site = callSites.callSite(
               from: node, propertyMap: receiverMap, fileName: fileName) {
            pendingCallSites.append(site)
        }
        return .visitChildren
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        if functionBodyDepth > 0,
           let assignment = callSites.assignment(from: node, fileName: fileName) {
            pendingAssignments.append(assignment)
        }
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        // A bare identifier or the member of a `self.x` access — recorded when it names a stored
        // property of the enclosing type (issue #111). Filtering to `callSitePropertyMap` keeps this
        // to own-field reads; consumers tolerate the same-name-local ambiguity as for assignments.
        if functionBodyDepth > 0,
           let read = callSites.fieldRead(
               from: node, propertyMap: callSitePropertyMap, fileName: fileName) {
            pendingFieldReads.append(read)
        }
        return .visitChildren
    }

}

// Stack management — in an extension so the visitor's main body stays within SwiftLint's
// `type_body_length`.
extension DeclarationVisitor {

    // MARK: - Stack Management

    private var currentNamespace: String? {
        typeStack.last?.qualifiedName
    }

    private func pushType(_ type: TypeDeclaration) {
        typeStack.append(type)
    }

    private func popType() {
        guard let completed = typeStack.popLast() else { return }
        if typeStack.isEmpty {
            types.append(completed)
        } else {
            typeStack[typeStack.count - 1].nestedTypes.append(completed)
        }
    }

    /// Builds a `varName → typeName` map from the stored properties already
    /// extracted for the current type.  Called just before descending into a
    /// function body so we know which receiver names can be resolved.
    private func buildPropertyMap() -> [String: String] {
        guard let currentType = typeStack.last else { return [:] }
        var map: [String: String] = [:]
        for member in currentType.members where member.kind == .property {
            if let typeName = member.type?.name {
                map[member.name] = typeName
            }
        }
        return map
    }

    /// Call sites gathered from every accessor body of a type-level `var`/`let` declaration, so a
    /// method reached only from a computed property (a SwiftUI `body`, a derived value) is not
    /// mistaken for dead code. Only reached at type scope — `visit` already skips local declarations.
    private func collectAccessorCallSites(from node: VariableDeclSyntax) -> [CallSite] {
        guard !typeStack.isEmpty else { return [] }
        let propertyMap = buildPropertyMap()
        var sites: [CallSite] = []
        for binding in node.bindings {
            guard let accessor = binding.accessorBlock else { continue }
            let walker = AccessorCallSiteWalker(
                collector: callSites, propertyMap: propertyMap, fileName: fileName)
            walker.walk(accessor)
            sites.append(contentsOf: walker.collected)
        }
        return sites
    }
}
