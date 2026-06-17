import UMLCore
import UMLTreeSitter

// MARK: - Program & Declaration Extraction

extension JavaExtractor {

    /// Actions for top-level source-file child nodes.
    private enum SourceFileAction {
        case setPackage
        case extractType
    }

    /// Dispatch table mapping source-file child node types to actions.
    private static let sourceFileDispatch: [String: SourceFileAction] = [
        "package_declaration": .setPackage,
        "class_declaration": .extractType,
        "interface_declaration": .extractType,
        "enum_declaration": .extractType,
        "record_declaration": .extractType,
        "annotation_type_declaration": .extractType
    ]

    mutating func walkSourceFile(_ node: Node) {
        for child in node.children() {
            guard let nodeType = child.nodeType,
                  let action = Self.sourceFileDispatch[nodeType] else { continue }
            switch action {
            case .setPackage:
                currentNamespace = extractPackageName(child)
            case .extractType:
                if let typeDecl = extractTopLevelType(child, nodeType: nodeType) {
                    types.append(typeDecl)
                }
            }
        }
    }

    /// Dispatches a type-declaration node to the appropriate extractor.
    mutating func extractTopLevelType(_ node: Node, nodeType: String) -> TypeDeclaration? {
        switch nodeType {
        case "class_declaration":
            return extractClassDeclaration(node)
        case "interface_declaration":
            return extractInterfaceDeclaration(node)
        case "enum_declaration":
            return extractEnumDeclaration(node)
        case "record_declaration":
            return extractRecordDeclaration(node)
        case "annotation_type_declaration":
            return extractAnnotationTypeDeclaration(node)
        default:
            return nil
        }
    }

    // MARK: - Package

    private func extractPackageName(_ node: Node) -> String? {
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "scoped_identifier" || nodeType == "identifier" {
                return text(child)
            }
        }
        return nil
    }

    // MARK: - Qualified Name Helpers

    func typeId(_ name: String) -> String { qualifiedName(name) }

    // MARK: - Modifiers

    // Lookup tables for modifier extraction (reduces cyclomatic complexity).
    private static let accessLevelMap: [String: AccessLevel] = [
        "public": .public, "private": .private, "protected": .protected
    ]
    private static let modifierMap: [String: Modifier] = [
        "static": .static, "final": .final, "abstract": .abstract,
        "synchronized": .synchronized, "volatile": .volatile,
        "transient": .transient, "native": .native,
        "strictfp": .strictfp, "default": .default
    ]

    func extractModifiers(_ node: Node) -> ModifierInfo {
        var accessLevel: AccessLevel?
        var modifiers: [Modifier] = []
        var annotations: [String] = []

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if let access = Self.accessLevelMap[nodeType] {
                accessLevel = access
            } else if let modifier = Self.modifierMap[nodeType] {
                modifiers.append(modifier)
            } else if nodeType == "marker_annotation" || nodeType == "annotation" {
                let keyword = text(child)
                annotations.append(keyword.hasPrefix("@") ? keyword : "@\(keyword)")
            }
        }

        return ModifierInfo(accessLevel: accessLevel, modifiers: modifiers, annotations: annotations)
    }

    func extractModifiersFromParent(_ node: Node) -> ModifierInfo {
        if let modifiersNode = node.firstChild(withType: "modifiers") {
            return extractModifiers(modifiersNode)
        }
        return ModifierInfo(accessLevel: nil, modifiers: [], annotations: [])
    }

    // MARK: - Class Declaration

    mutating func extractClassDeclaration(_ node: Node) -> TypeDeclaration? {
        let modifierInfo = extractModifiersFromParent(node)
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)
        let nodeLoc = loc(node)

        let genericParams = extractTypeParameters(from: node)
        var inheritedTypes: [TypeReference] = []

        if let superclassNode = node.child(byFieldName: "superclass") {
            for superType in extractSuperclassTypes(superclassNode) {
                inheritedTypes.append(superType)
                relationships.append(
                    Relationship(kind: .inheritance, source: qualifiedTypeName, target: superType.name)
                )
            }
        }

        if let interfacesNode = node.child(byFieldName: "interfaces") {
            for ifaceType in extractTypeList(interfacesNode) {
                inheritedTypes.append(ifaceType)
                relationships.append(
                    Relationship(kind: .conformance, source: qualifiedTypeName, target: ifaceType.name)
                )
            }
        }

        var bodyContext = BodyExtractionContext(parentQualifiedName: qualifiedTypeName)

        if let bodyNode = node.child(byFieldName: "body") {
            extractClassBody(bodyNode, context: &bodyContext)
        }

        return TypeDeclaration(
            id: typeId(name), name: name, qualifiedName: qualifiedTypeName, kind: .class,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            genericParameters: genericParams, inheritedTypes: inheritedTypes,
            members: bodyContext.members, enumCases: bodyContext.enumCases,
            nestedTypes: bodyContext.nestedTypes,
            annotations: modifierInfo.annotations, namespace: currentNamespace, location: nodeLoc
        )
    }

    // MARK: - Interface Declaration

    mutating func extractInterfaceDeclaration(_ node: Node) -> TypeDeclaration? {
        let modifierInfo = extractModifiersFromParent(node)
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)
        let nodeLoc = loc(node)

        let genericParams = extractTypeParameters(from: node)
        var inheritedTypes: [TypeReference] = []

        for child in node.children() {
            guard child.nodeType == "extends_interfaces" else { continue }
            for extType in extractTypeList(child) {
                inheritedTypes.append(extType)
                relationships.append(Relationship(kind: .conformance, source: qualifiedTypeName, target: extType.name))
            }
        }

        var bodyContext = BodyExtractionContext(parentQualifiedName: qualifiedTypeName)

        if let bodyNode = node.child(byFieldName: "body") {
            extractInterfaceBody(bodyNode, context: &bodyContext)
        }

        return TypeDeclaration(
            id: typeId(name), name: name, qualifiedName: qualifiedTypeName, kind: .interface,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            genericParameters: genericParams, inheritedTypes: inheritedTypes,
            members: bodyContext.members, enumCases: bodyContext.enumCases,
            nestedTypes: bodyContext.nestedTypes,
            annotations: modifierInfo.annotations, namespace: currentNamespace, location: nodeLoc
        )
    }

    // MARK: - Enum Declaration

    mutating func extractEnumDeclaration(_ node: Node) -> TypeDeclaration? {
        let modifierInfo = extractModifiersFromParent(node)
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)
        let nodeLoc = loc(node)

        var inheritedTypes: [TypeReference] = []
        if let interfacesNode = node.child(byFieldName: "interfaces") {
            for ifaceType in extractTypeList(interfacesNode) {
                inheritedTypes.append(ifaceType)
                relationships.append(
                    Relationship(kind: .conformance, source: qualifiedTypeName, target: ifaceType.name)
                )
            }
        }

        var bodyContext = BodyExtractionContext(parentQualifiedName: qualifiedTypeName)

        if let bodyNode = node.child(byFieldName: "body") {
            extractEnumBody(bodyNode, context: &bodyContext)
        }

        return TypeDeclaration(
            id: typeId(name), name: name, qualifiedName: qualifiedTypeName, kind: .enum,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            inheritedTypes: inheritedTypes, members: bodyContext.members,
            enumCases: bodyContext.enumCases, nestedTypes: bodyContext.nestedTypes,
            annotations: modifierInfo.annotations, namespace: currentNamespace, location: nodeLoc
        )
    }

    // MARK: - Record Declaration

    mutating func extractRecordDeclaration(_ node: Node) -> TypeDeclaration? {
        let modifierInfo = extractModifiersFromParent(node)
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)
        let nodeLoc = loc(node)

        let genericParams = extractTypeParameters(from: node)
        var inheritedTypes: [TypeReference] = []
        if let interfacesNode = node.child(byFieldName: "interfaces") {
            for ifaceType in extractTypeList(interfacesNode) {
                inheritedTypes.append(ifaceType)
                relationships.append(
                    Relationship(kind: .conformance, source: qualifiedTypeName, target: ifaceType.name)
                )
            }
        }

        var bodyContext = BodyExtractionContext(parentQualifiedName: qualifiedTypeName)
        if let paramsNode = node.child(byFieldName: "parameters") {
            for component in extractRecordComponents(paramsNode) {
                bodyContext.members.append(Member(
                    name: component.internalName, kind: .property,
                    accessLevel: .public, type: component.type, location: nodeLoc
                ))
            }
        }

        if let bodyNode = node.child(byFieldName: "body") {
            extractClassBody(bodyNode, context: &bodyContext)
        }

        return TypeDeclaration(
            id: typeId(name), name: name, qualifiedName: qualifiedTypeName, kind: .record,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            genericParameters: genericParams, inheritedTypes: inheritedTypes,
            members: bodyContext.members, enumCases: bodyContext.enumCases,
            nestedTypes: bodyContext.nestedTypes,
            annotations: modifierInfo.annotations, namespace: currentNamespace, location: nodeLoc
        )
    }

    private func extractRecordComponents(_ node: Node) -> [Parameter] {
        var params: [Parameter] = []
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "formal_parameter" || nodeType == "spread_parameter" {
                if let param = extractFormalParameter(child) { params.append(param) }
            }
        }
        return params
    }

    // MARK: - Annotation Type Declaration

    mutating func extractAnnotationTypeDeclaration(_ node: Node) -> TypeDeclaration? {
        let modifierInfo = extractModifiersFromParent(node)
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)
        let nodeLoc = loc(node)

        var bodyContext = BodyExtractionContext(parentQualifiedName: qualifiedTypeName)

        if let bodyNode = node.child(byFieldName: "body") {
            extractAnnotationTypeBody(bodyNode, context: &bodyContext)
        }

        return TypeDeclaration(
            id: typeId(name), name: name, qualifiedName: qualifiedTypeName, kind: .annotation,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            members: bodyContext.members, nestedTypes: bodyContext.nestedTypes,
            annotations: modifierInfo.annotations, namespace: currentNamespace, location: nodeLoc
        )
    }
}
