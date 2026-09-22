import AcaiCore
import AcaiTreeSitter

/// Walks a Kotlin file and builds its `CodeArtifact`, sequencing collaborators that each own one
/// concern. Every collaborator is built once, in `init`.
struct KotlinExtractor {

    let context: SourceFileContext
    let modifiers: KotlinModifiers
    let typeReferences: KotlinTypeReferenceResolver
    let parameterExtractor: KotlinParameterExtractor
    let memberExtractor: KotlinMemberExtractor

    var declarations = DeclarationBuilder()

    /// Takes the tree so the declared-type pre-pass runs before the collaborators that read it.
    init(source: String, fileName: String, root: Node) {
        let context = SourceFileContext(source: source, fileName: fileName)
        let declaredTypeNames = TypeNamePrepass(declarationNodeTypes: ["class_declaration", "object_declaration"])
            .names(in: root) { $0.firstChild(withType: "type_identifier").map { $0.text(in: context) } }

        self.context = context
        modifiers = KotlinModifiers(context: context)
        typeReferences = KotlinTypeReferenceResolver(context: context)
        parameterExtractor = KotlinParameterExtractor(
            context: context, typeReferences: typeReferences, modifiers: modifiers)
        let assignmentSyntax = KotlinAssignmentSyntax(context: context)
        memberExtractor = KotlinMemberExtractor(
            context: context, typeReferences: typeReferences, modifiers: modifiers,
            parameterExtractor: parameterExtractor, assignmentSyntax: assignmentSyntax,
            callSites: CallSiteResolver(
                syntax: KotlinCallSiteSyntax(context: context, declaredTypeNames: declaredTypeNames)
            ),
            assignments: AssignmentResolver(syntax: assignmentSyntax),
            // Bare references and `this.<prop>` navigation members are both `simple_identifier` nodes.
            fieldReads: FieldReadResolver(context: context, identifierTypes: ["simple_identifier"]),
            declaredTypeNames: declaredTypeNames
        )

        declarations.declaredTypeNames = declaredTypeNames
    }

    // MARK: - Public Entry Point

    mutating func extract(from root: Node) -> CodeArtifact {
        walkSourceFile(root)
        declarations.resolveRelationshipNames()
        return declarations.artifact(language: .kotlin, filePath: context.fileName)
    }

    // MARK: - Function Declaration

    /// An extension function (`fun String.hello() {}`) also records its receiver as an `.extension`
    /// edge, which only the extractor's declaration state can hold.
    mutating func extractFunctionDeclaration(_ node: Node, scope: CallSiteScope = CallSiteScope()) -> Member {
        if let receiverRef = memberExtractor.receiverType(of: node) {
            let name = node.firstChild(withType: "simple_identifier").map { $0.text(in: context) } ?? "_anonymous"
            declarations.relationships.append(
                Relationship(kind: .extension, source: name, target: receiverRef.name)
            )
        }
        return memberExtractor.functionDeclaration(node, scope: scope)
    }
}

// MARK: - Source File

extension KotlinExtractor {

    private enum SourceFileAction {
        case setPackage
        case classDeclaration
        case objectDeclaration
        case functionDeclaration
        case propertyDeclaration
        case typeAlias
    }

    private static let sourceFileDispatch: [String: SourceFileAction] = [
        "package_header": .setPackage,
        "class_declaration": .classDeclaration,
        "object_declaration": .objectDeclaration,
        "function_declaration": .functionDeclaration,
        "property_declaration": .propertyDeclaration,
        "type_alias": .typeAlias
    ]

    mutating func walkSourceFile(_ node: Node) {
        for (child, action) in NodeDispatch(Self.sourceFileDispatch).matches(in: node) {
            performSourceFileAction(action, on: child)
        }
    }

    private mutating func performSourceFileAction(_ action: SourceFileAction, on node: Node) {
        switch action {
        case .setPackage:
            if let packageName = node.firstChild(withType: "identifier")?.text(in: context) {
                _ = declarations.enter(namespace: packageName)
            }
        case .classDeclaration:
            handleClassDeclaration(node)
        case .objectDeclaration:
            if let typeDecl = extractObjectDeclaration(node) {
                declarations.types.append(typeDecl)
            }
        case .functionDeclaration:
            declarations.freestandingFunctions.append(
                extractFunctionDeclaration(node)
            )
        case .propertyDeclaration:
            declarations.globalVariables.append(memberExtractor.propertyDeclaration(node))
        case .typeAlias:
            if let typeDecl = extractTypeAlias(node) {
                declarations.types.append(typeDecl)
            }
        }
    }

    private mutating func handleClassDeclaration(_ child: Node) {
        if child.hasDirectChildText("interface", in: context) {
            if let typeDecl = extractInterfaceDeclaration(child) {
                declarations.types.append(typeDecl)
            }
        } else {
            if let typeDecl = extractClassDeclaration(child) {
                declarations.types.append(typeDecl)
            }
        }
    }
}

// MARK: - Type Declarations

extension KotlinExtractor {

    // MARK: - Class Declaration

    mutating func extractClassDeclaration(_ node: Node) -> TypeDeclaration? {
        let modifierInfo = modifiers.info(fromParentOf: node)

        if node.hasChild(withType: "enum_class_body") {
            return extractEnumClassDeclaration(node, modifierInfo: modifierInfo)
        }

        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = nameNode.text(in: context)
        let qualifiedTypeName = declarations.qualifiedName(name)

        let generics = typeReferences.extractTypeParameters(node.firstChild(withType: "type_parameters"))
        let ctorNode = node.firstChild(withType: "primary_constructor")
        let ctorAccess = ctorNode
            .flatMap { $0.firstChild(withType: "modifiers") }
            .map { modifiers.info(for: $0).accessLevel } ?? modifierInfo.accessLevel
        let ctorParams = parameterExtractor.primaryConstructorParams(ctorNode)
        let supertypes = typeReferences.classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        let isAnnotation = node.firstChild(withType: "modifiers")?.namedChildren()
            .contains { $0.nodeType == "class_modifier" && $0.text(in: context) == "annotation" } ?? false

        var typeDecl = TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName,
            kind: isAnnotation ? .annotation : .class,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            genericParameters: generics, inheritedTypes: supertypes.map(\.typeRef),
            annotations: modifierInfo.annotations, namespace: declarations.currentNamespace,
            location: node.location(in: context)
        )

        // Promoted constructor properties — each carries its own access level.
        for constructorParam in ctorParams where constructorParam.isProperty {
            var modifiers = constructorParam.modifiers
            if constructorParam.isReadOnly { modifiers.append(.readonly) }
            typeDecl.members.append(Member(
                name: constructorParam.parameter.internalName, kind: .property,
                accessLevel: constructorParam.accessLevel, modifiers: modifiers,
                type: constructorParam.parameter.type, annotations: constructorParam.annotations
            ))
        }
        if !ctorParams.isEmpty {
            typeDecl.members.append(Member(
                name: "init", kind: .initializer,
                accessLevel: ctorAccess,
                parameters: ctorParams.map(\.parameter)
            ))
        }

        for supertype in supertypes {
            declarations.relationships.append(supertype.typeRef.relationship(
                kind: supertype.isClassInheritance ? .inheritance : .conformance, source: qualifiedTypeName
            ))
        }
        if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Interface

    mutating func extractInterfaceDeclaration(_ node: Node) -> TypeDeclaration? {
        let modifierInfo = modifiers.info(fromParentOf: node)
        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = nameNode.text(in: context)
        let qualifiedTypeName = declarations.qualifiedName(name)

        let generics = typeReferences.extractTypeParameters(node.firstChild(withType: "type_parameters"))
        let supertypes = typeReferences.classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        var typeDecl = TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName, kind: .interface,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            genericParameters: generics, inheritedTypes: supertypes.map(\.typeRef),
            annotations: modifierInfo.annotations, namespace: declarations.currentNamespace,
            location: node.location(in: context)
        )
        for supertype in supertypes {
            declarations.relationships.append(
                supertype.typeRef.relationship(kind: .conformance, source: qualifiedTypeName)
            )
        }
        if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Object Declaration

    mutating func extractObjectDeclaration(_ node: Node) -> TypeDeclaration? {
        let modifierInfo = modifiers.info(fromParentOf: node)
        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = nameNode.text(in: context)
        let qualifiedTypeName = declarations.qualifiedName(name)
        let supertypes = typeReferences.classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        var typeDecl = TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName, kind: .object,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            inheritedTypes: supertypes.map(\.typeRef),
            annotations: modifierInfo.annotations, namespace: declarations.currentNamespace,
            location: node.location(in: context)
        )
        for supertype in supertypes {
            declarations.relationships.append(supertype.typeRef.relationship(
                kind: supertype.isClassInheritance ? .inheritance : .conformance, source: qualifiedTypeName
            ))
        }
        if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Companion Object

    mutating func extractCompanionObject(_ node: Node) -> TypeDeclaration? {
        let name = node.firstChild(withType: "type_identifier").map { $0.text(in: context) } ?? "Companion"
        let qualifiedTypeName = declarations.qualifiedName(name)
        let supertypes = typeReferences.classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        var typeDecl = TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName,
            kind: .object, accessLevel: .public, modifiers: [.static],
            inheritedTypes: supertypes.map(\.typeRef),
            namespace: declarations.currentNamespace, location: node.location(in: context)
        )
        for supertype in supertypes {
            declarations.relationships.append(supertype.typeRef.relationship(
                kind: supertype.isClassInheritance ? .inheritance : .conformance, source: qualifiedTypeName
            ))
        }
        if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Enum Class

    mutating func extractEnumClassDeclaration(
        _ node: Node,
        modifierInfo: ModifierInfo
    ) -> TypeDeclaration? {
        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = nameNode.text(in: context)
        let qualifiedTypeName = declarations.qualifiedName(name)

        let generics = typeReferences.extractTypeParameters(node.firstChild(withType: "type_parameters"))
        let supertypes = typeReferences.classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        var typeDecl = TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName, kind: .enum,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            genericParameters: generics, inheritedTypes: supertypes.map(\.typeRef),
            annotations: modifierInfo.annotations, namespace: declarations.currentNamespace,
            location: node.location(in: context)
        )
        for supertype in supertypes {
            declarations.relationships.append(supertype.typeRef.relationship(
                kind: supertype.isClassInheritance ? .inheritance : .conformance, source: qualifiedTypeName
            ))
        }
        if let body = node.firstChild(withType: "enum_class_body") {
            for child in body.namedChildren() where child.nodeType == "enum_entry" {
                if let enumCase = memberExtractor.enumEntry(child) { typeDecl.enumCases.append(enumCase) }
            }
            extractBody(body, into: &typeDecl, skipEnumEntries: true)
        } else if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Type Alias

    func extractTypeAlias(_ node: Node) -> TypeDeclaration? {
        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = nameNode.text(in: context)
        let qualifiedTypeName = declarations.qualifiedName(name)
        let modifierInfo = modifiers.info(fromParentOf: node)
        let generics = typeReferences.extractTypeParameters(node.firstChild(withType: "type_parameters"))

        var targetType: [TypeReference] = []
        if let userTypeNode = node.firstChild(withType: "user_type") {
            targetType.append(typeReferences.extractTypeReference(userTypeNode))
        } else if let nullableTypeNode = node.firstChild(withType: "nullable_type") {
            targetType.append(typeReferences.extractNullableType(nullableTypeNode))
        }

        return TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName, kind: .typeAlias,
            accessLevel: modifierInfo.accessLevel, genericParameters: generics,
            inheritedTypes: targetType, annotations: modifierInfo.annotations,
            namespace: declarations.currentNamespace, location: node.location(in: context)
        )
    }
}

// MARK: - Body Extraction

extension KotlinExtractor {

    /// Extracts members, nested types, and companion objects from a class/interface/object body.
    /// Used for both `class_body` and `enum_class_body` nodes.
    mutating func extractBody(
        _ node: Node,
        into typeDecl: inout TypeDeclaration,
        skipEnumEntries: Bool = false
    ) {
        // Parent type's qualified ID as namespace, so nested types get correctly-qualified IDs.
        let outerNamespace = declarations.enter(namespace: typeDecl.id)
        defer { declarations.leave(outerNamespace) }

        // Pre-scan: build property → type map for call-site resolution.
        var knownProperties = MemberIndex(members: typeDecl.members).propertyTypes
        for child in node.namedChildren()
            where child.nodeType == "property_declaration" {
            let prop = memberExtractor.propertyDeclaration(child)
            if !prop.modifiers.contains(.static),
               let typeName = prop.type?.name {
                knownProperties[prop.name] = typeName
            }
        }

        // Pre-scan: build methodName → returnType map (unambiguous overloads only), so a same-type
        // method call, including one declared later in the type, can seed a local's type.
        var returnTypes = UnambiguousTypeNames()
        for child in node.namedChildren() where child.nodeType == "function_declaration" {
            guard let nameNode = child.firstChild(withType: "simple_identifier"),
                  let returnTypeNode = memberExtractor.returnTypeNode(in: child)
            else { continue }
            let returnType = typeReferences.extractTypeReferenceFromAny(returnTypeNode)
            guard returnType.name != "Unit" else { continue }
            returnTypes.record(returnType.name, for: nameNode.text(in: context))
        }

        let scope = CallSiteScope(
            knownProperties: knownProperties,
            knownTypeNames: declarations.declaredTypeNames,
            knownMethodReturnTypes: returnTypes.resolved
        )

        let namedChildren = node.namedChildren()
        var bodyContext = BodyChildContext(
            siblings: namedChildren,
            typeDecl: typeDecl,
            scope: scope,
            skipEnumEntries: skipEnumEntries
        )
        for (index, child) in namedChildren.enumerated() {
            handleBodyChild(child, at: index, context: &bodyContext)
        }
        typeDecl = bodyContext.typeDecl
    }

    private struct BodyChildContext {
        let siblings: [Node]
        var typeDecl: TypeDeclaration
        let scope: CallSiteScope
        let skipEnumEntries: Bool
    }

    private mutating func handleBodyChild(
        _ child: Node,
        at index: Int,
        context: inout BodyChildContext
    ) {
        switch child.nodeType {
        case "enum_entry" where context.skipEnumEntries:
            return
        case "function_declaration":
            context.typeDecl.members.append(extractFunctionDeclaration(child, scope: context.scope))
        case "property_declaration":
            let hasGetterOrSetter = nextSiblingIsAccessor(at: index, in: context.siblings)
            context.typeDecl.members.append(
                memberExtractor.propertyDeclaration(child, isComputed: hasGetterOrSetter, scope: context.scope)
            )
        case "anonymous_initializer":
            // An `init { … }` block — Kotlin's real constructor body. Record its calls on an
            // `.initializer` member so they're never a dead-code false positive.
            context.typeDecl.members.append(memberExtractor.anonymousInitializer(child, scope: context.scope))
        case "secondary_constructor":
            context.typeDecl.members.append(memberExtractor.secondaryConstructor(child, scope: context.scope))
        case "companion_object", "class_declaration", "object_declaration":
            handleNestedTypeChild(child, into: &context.typeDecl)
        default:
            break
        }
    }

    private mutating func handleNestedTypeChild(_ child: Node, into typeDecl: inout TypeDeclaration) {
        switch child.nodeType {
        case "companion_object":
            if let obj = extractCompanionObject(child) { typeDecl.nestedTypes.append(obj) }
        case "object_declaration":
            if let nestedType = extractObjectDeclaration(child) { typeDecl.nestedTypes.append(nestedType) }
        default:
            handleNestedClassDeclaration(child, into: &typeDecl)
        }
    }

    private func nextSiblingIsAccessor(
        at index: Int, in siblings: [Node]
    ) -> Bool {
        let next = index + 1
        guard next < siblings.count else { return false }
        let sibling = siblings[next].nodeType
        return sibling == "getter" || sibling == "setter"
    }

    private mutating func handleNestedClassDeclaration(
        _ child: Node, into typeDecl: inout TypeDeclaration
    ) {
        if child.hasDirectChildText("interface", in: context) {
            if let nestedType = extractInterfaceDeclaration(child) {
                typeDecl.nestedTypes.append(nestedType)
            }
        } else if let nestedType = extractClassDeclaration(child) {
            typeDecl.nestedTypes.append(nestedType)
        }
    }
}
