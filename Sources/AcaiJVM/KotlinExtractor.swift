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
    let documentation = DocumentationReader(
        convention: DocumentationComment(blockOpenings: ["/**"]),
        commentNodeTypes: ["multiline_comment", "line_comment", "comment"]
    )

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
            let mark = declarations.mark
            performSourceFileAction(action, on: child)
            declarations.attachDocumentation(documentation.documentation(above: child, in: context), since: mark)
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
            appendTopLevelFunction(node)
        case .propertyDeclaration:
            declarations.globalVariables.append(memberExtractor.propertyDeclaration(node))
        case .typeAlias:
            if let typeDecl = extractTypeAlias(node) {
                declarations.types.append(typeDecl)
            }
        }
    }

    /// An extension function on a type declared in this artifact (`fun Box.extra()`) augments that
    /// type, so it becomes an `.extension` declaration holding the member — the shape enrichment
    /// merges into the extended type, as it does for a Swift `extension` or a Dart `extension … on`.
    private mutating func appendTopLevelFunction(_ node: Node) {
        let receiver = memberExtractor.receiverType(of: node)
        let member = extractFunctionDeclaration(node)
        guard let receiver, declarations.declaredTypeNames.contains(receiver.name) else {
            declarations.freestandingFunctions.append(member)
            return
        }
        let qualifiedName = declarations.qualifiedName(receiver.name)
        declarations.types.append(TypeDeclaration(
            id: "extension.\(qualifiedName).\(member.name)",
            name: receiver.name,
            qualifiedName: qualifiedName,
            kind: .extension,
            accessLevel: member.accessLevel,
            members: [member],
            extensionOf: receiver.name,
            namespace: declarations.currentNamespace,
            location: node.location(in: context)
        ))
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
                guard var enumCase = memberExtractor.enumEntry(child) else { continue }
                enumCase.documentation = documentation.documentation(above: child, in: context)
                typeDecl.enumCases.append(enumCase)
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
