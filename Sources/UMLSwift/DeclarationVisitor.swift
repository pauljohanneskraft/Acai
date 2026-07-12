import SwiftSyntax
import UMLCore

final class DeclarationVisitor: SyntaxVisitor {
    private let fileName: String
    private var types: [TypeDeclaration] = []
    private var relationships: [Relationship] = []
    private var freestandingFunctions: [Member] = []
    private var globalVariables: [Member] = []
    private var typeStack: [TypeDeclaration] = []
    // Mirrors `typeStack`: each entry is the current type's `methodName → returnType` map (RC-I),
    // pre-passed from the raw syntax so a forward-declared method's return type is seen too.
    private var methodReturnTypeMapStack: [[String: String]] = []

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
    // Maps the current function/initializer's parameter name → declared type, so `param.method()`
    // resolves the same way a typed stored property does. Kept separate from the property map for
    // the same reason as `callSiteLocalMap`: a parameter is a call-site receiver, not a field.
    private var callSiteParameterMap: [String: String] = [:]
    // Call sites made by bare top-level statements (a `main.swift`-style script), outside any
    // function or type body. Attached to a synthetic always-reachable freestanding member in
    // `buildArtifact()` so a callee reached only from top-level code isn't a dead-code false
    // positive (RC-H).
    private var topLevelCallSites: [CallSite] = []
    // Simple names of every type declared in the file, seeded up front (in one pre-pass)
    // so `TypeName.method()` static calls resolve regardless of declaration order — including
    // forward-declared siblings — without misclassifying calls on unknown/external receivers.
    private let knownTypeNames: Set<String>
    // Each same-file protocol's requirement properties (`var x: T { get }`), keyed by protocol name
    // and seeded up front — a protocol extension's default implementation calling through one of
    // these (`history.undo()`) otherwise can't resolve, since the property lives on the protocol, not
    // the extension's own member list.
    private let protocolProperties: [String: [String: String]]

    // Composable extractors: each owns one slice of the SwiftSyntax-to-model mapping, so this visitor
    // delegates rather than depending on every syntax node type directly.
    private let typeDeclarations = TypeDeclarationExtractor()
    private let members: MemberExtractor
    private let signatures = DeclarationSignatureExtractor()
    private let callSites: CallSiteCollector

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
        // functions we don't descend into — otherwise the counter underflows and
        // every later declaration in the file is silently dropped.
        let isNested = functionBodyDepth > 0
        functionBodyDepth += 1
        // Inside another function body: skip the nested function entirely.
        guard !isNested else { return .skipChildren }

        // Capture the property map for this type before we descend.
        callSitePropertyMap = buildPropertyMap()
        callSiteLocalMap = [:]
        callSiteParameterMap = parameterMap(from: node.signature.parameterClause)
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
            let returnTypes = methodReturnTypeMapStack.last ?? [:]
            for binding in node.bindings {
                if let local = callSites.localBinding(from: binding, methodReturnTypes: returnTypes) {
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
        callSiteParameterMap = parameterMap(from: node.signature.parameterClause)
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
        // Parameters and locals resolve receivers too, but they must not leak into field-read
        // detection, so they're merged in only here (parameters, then locals, shadowing same-named
        // stored properties — and each other, in declaration order).
        var receiverMap = callSitePropertyMap
        if !callSiteParameterMap.isEmpty {
            receiverMap.merge(callSiteParameterMap) { _, parameter in parameter }
        }
        if !callSiteLocalMap.isEmpty {
            receiverMap.merge(callSiteLocalMap) { _, local in local }
        }
        if functionBodyDepth > 0,
           let site = callSites.callSite(
               from: node, propertyMap: receiverMap,
               enclosingTypeName: typeStack.last?.name, fileName: fileName) {
            pendingCallSites.append(site)
        } else if functionBodyDepth == 0, typeStack.isEmpty,
                  let site = callSites.callSite(
                    from: node, propertyMap: topLevelGlobalPropertyMap(),
                    enclosingTypeName: nil, fileName: fileName) {
            // A bare top-level statement (a `main.swift`-style script): its calls have nowhere to
            // attach as a member, so they're recorded separately and given a synthetic reachable
            // member in `buildArtifact()` (RC-H). Receivers resolve against `globalVariables`
            // declared earlier in the file (Swift's top-level execution order guarantees a global's
            // declaration precedes its use), the top-level analogue of `callSitePropertyMap`.
            topLevelCallSites.append(site)
        }
        return .visitChildren
    }

    /// `globalName → typeName` for every top-level `let`/`var` with a provable type, built fresh at
    /// each top-level call site so it reflects every global declared so far.
    private func topLevelGlobalPropertyMap() -> [String: String] {
        Dictionary(
            globalVariables.compactMap { global in global.type.map { (global.name, $0.name) } },
            uniquingKeysWith: { first, _ in first }
        )
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

    private func pushType(_ type: TypeDeclaration, memberBlock: MemberBlockSyntax) {
        typeStack.append(type)
        methodReturnTypeMapStack.append(returnTypeMap(from: memberBlock))
    }

    private func popType() {
        guard let completed = typeStack.popLast() else { return }
        methodReturnTypeMapStack.removeLast()
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
    private func returnTypeMap(from memberBlock: MemberBlockSyntax) -> [String: String] {
        var typesByName: [String: Set<String>] = [:]
        for item in memberBlock.members {
            guard let function = item.decl.as(FunctionDeclSyntax.self),
                  let returnType = function.signature.returnClause?.type.as(IdentifierTypeSyntax.self)
            else { continue }
            typesByName[function.name.text, default: []].insert(returnType.name.text)
        }
        return typesByName.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    /// Builds a `varName → typeName` map from the stored properties already
    /// extracted for the current type.  Called just before descending into a
    /// function body so we know which receiver names can be resolved.
    ///
    /// When the current type is a protocol extension, also seeds the extended protocol's own
    /// requirement properties (`var x: T { get }`) — the extension's own member list never carries
    /// them (they're declared on the protocol, not the extension), so a default implementation
    /// calling through one (`history.undo()`) would otherwise be unresolvable.
    private func buildPropertyMap() -> [String: String] {
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

    /// Builds a `paramName → typeName` map from a function/initializer's parameter list, so a
    /// `param.method()` call inside the body resolves. Only parameters with a provable simple type
    /// name are included (mirrors `buildPropertyMap`'s "typed only" bar).
    private func parameterMap(from parameterClause: FunctionParameterClauseSyntax) -> [String: String] {
        var map: [String: String] = [:]
        for parameter in signatures.extractParameters(from: parameterClause) {
            if let typeName = parameter.type?.name {
                map[parameter.internalName] = typeName
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
                collector: callSites, propertyMap: propertyMap,
                enclosingTypeName: typeStack.last?.name,
                methodReturnTypes: methodReturnTypeMapStack.last ?? [:], fileName: fileName)
            walker.walk(accessor)
            sites.append(contentsOf: walker.collected)
        }
        return sites
    }
}
