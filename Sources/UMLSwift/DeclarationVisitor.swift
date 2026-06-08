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
    // Maps stored-property name → declared type name for the current type.
    private var callSitePropertyMap: [String: String] = [:]

    init(fileName: String) {
        self.fileName = fileName
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
        let typeDecl = TypeExtractor.extractClass(from: node, fileName: fileName, namespace: currentNamespace)
        pushType(typeDecl)
        relationships.append(contentsOf: RelationshipExtractor.extract(from: node, typeId: typeDecl.id))
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        guard functionBodyDepth == 0 else { return }
        popType()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0 else { return .skipChildren }
        let typeDecl = TypeExtractor.extractStruct(from: node, fileName: fileName, namespace: currentNamespace)
        pushType(typeDecl)
        relationships.append(contentsOf: RelationshipExtractor.extract(from: node, typeId: typeDecl.id))
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        guard functionBodyDepth == 0 else { return }
        popType()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0 else { return .skipChildren }
        let typeDecl = TypeExtractor.extractEnum(from: node, fileName: fileName, namespace: currentNamespace)
        pushType(typeDecl)
        relationships.append(contentsOf: RelationshipExtractor.extract(from: node, typeId: typeDecl.id))
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        guard functionBodyDepth == 0 else { return }
        popType()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0 else { return .skipChildren }
        let typeDecl = TypeExtractor.extractProtocol(from: node, fileName: fileName, namespace: currentNamespace)
        pushType(typeDecl)
        relationships.append(contentsOf: RelationshipExtractor.extract(from: node, typeId: typeDecl.id))
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
        let typeDecl = TypeExtractor.extractExtension(from: node, fileName: fileName, namespace: currentNamespace)
        pushType(typeDecl)
        relationships.append(contentsOf: RelationshipExtractor.extract(from: node, typeId: typeDecl.id))
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        guard functionBodyDepth == 0 else { return }
        popType()
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0 else { return .skipChildren }
        let typeDecl = TypeExtractor.extractTypeAlias(from: node, fileName: fileName, namespace: currentNamespace)
        if typeStack.isEmpty {
            types.append(typeDecl)
        } else {
            typeStack[typeStack.count - 1].nestedTypes.append(typeDecl)
        }
        return .skipChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0 else { return .skipChildren }
        let typeDecl = TypeExtractor.extractActor(from: node, fileName: fileName, namespace: currentNamespace)
        pushType(typeDecl)
        relationships.append(contentsOf: RelationshipExtractor.extract(from: node, typeId: typeDecl.id))
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
        pendingCallSites = []
        return .visitChildren   // descend so FunctionCallExprSyntax nodes are visited
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        functionBodyDepth -= 1
        // Only the top-of-body function becomes a member; nested ones are skipped.
        guard functionBodyDepth == 0 else { return }
        let member = TypeExtractor.extractFunction(
            from: node, fileName: fileName, callSites: pendingCallSites)
        pendingCallSites = []
        callSitePropertyMap = [:]
        if typeStack.isEmpty {
            freestandingFunctions.append(member)
        } else {
            typeStack[typeStack.count - 1].members.append(member)
        }
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Skip local variables inside function bodies.
        guard functionBodyDepth == 0 else { return .skipChildren }
        let members = TypeExtractor.extractVariable(from: node, fileName: fileName)
        if typeStack.isEmpty {
            // Top-level (module-scope) `let`/`var`.
            globalVariables.append(contentsOf: members)
        } else {
            typeStack[typeStack.count - 1].members.append(contentsOf: members)
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
        pendingCallSites = []
        return .visitChildren
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        functionBodyDepth -= 1
        guard functionBodyDepth == 0, !typeStack.isEmpty else { return }
        let member = TypeExtractor.extractInitializer(
            from: node, fileName: fileName, callSites: pendingCallSites)
        pendingCallSites = []
        callSitePropertyMap = [:]
        typeStack[typeStack.count - 1].members.append(member)
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0, !typeStack.isEmpty else { return .skipChildren }
        let member = TypeExtractor.extractDeinitializer(from: node, fileName: fileName)
        typeStack[typeStack.count - 1].members.append(member)
        return .skipChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0, !typeStack.isEmpty else { return .skipChildren }
        let member = TypeExtractor.extractSubscript(from: node, fileName: fileName)
        typeStack[typeStack.count - 1].members.append(member)
        return .skipChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0, !typeStack.isEmpty else { return .skipChildren }
        let cases = TypeExtractor.extractEnumCases(from: node, fileName: fileName)
        typeStack[typeStack.count - 1].enumCases.append(contentsOf: cases)
        return .skipChildren
    }

    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        guard functionBodyDepth == 0, !typeStack.isEmpty else { return .skipChildren }
        typeStack[typeStack.count - 1].associatedTypes.append(
            TypeExtractor.extractAssociatedType(from: node))
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

    // MARK: - Call-Site Collection

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if functionBodyDepth > 0,
           let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            let methodName = memberAccess.declName.baseName.text
            if let receiverType = resolveCallSiteReceiver(from: memberAccess.base) {
                pendingCallSites.append(CallSite(
                    receiverType: receiverType,
                    methodName: methodName,
                    location: TypeExtractor.sourceLocation(of: node, fileName: fileName)
                ))
            }
        }
        return .visitChildren
    }

    /// Resolves the declared type for a receiver expression using `callSitePropertyMap`.
    ///
    /// Handles:
    /// - `varName.method()` — direct lookup
    /// - `self.varName.method()` — strips the leading `self.` then looks up
    private func resolveCallSiteReceiver(from base: ExprSyntax?) -> String? {
        guard let base else { return nil }

        if let declRef = base.as(DeclReferenceExprSyntax.self) {
            return callSitePropertyMap[declRef.baseName.text]
        }

        if let memberAccess = base.as(MemberAccessExprSyntax.self),
           memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "self" {
            return callSitePropertyMap[memberAccess.declName.baseName.text]
        }

        return nil
    }

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
}
