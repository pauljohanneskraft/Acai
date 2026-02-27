import UMLCore
import UMLTreeSitter

struct JavaExtractor: TreeSitterExtracting, CallSiteResolving {
    let context: SourceFileContext

    var types: [TypeDeclaration] = []
    var relationships: [Relationship] = []
    var freestandingFunctions: [Member] = []
    var currentNamespace: String?

    init(source: String, fileName: String) {
        self.context = SourceFileContext(source: source, fileName: fileName)
    }

    // MARK: - Public

    mutating func extract(from root: Node) -> CodeArtifact {
        walkSourceFile(root)
        return buildArtifact(language: .java)
    }
}

// MARK: - Program & Declaration Extraction

extension JavaExtractor {

    mutating func walkSourceFile(_ node: Node) {
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "package_declaration":
                currentNamespace = extractPackageName(child)
            case "import_declaration":
                break // Skip imports
            case "class_declaration":
                if let typeDecl = extractClassDeclaration(child) { types.append(typeDecl) }
            case "interface_declaration":
                if let typeDecl = extractInterfaceDeclaration(child) { types.append(typeDecl) }
            case "enum_declaration":
                if let typeDecl = extractEnumDeclaration(child) { types.append(typeDecl) }
            case "record_declaration":
                if let typeDecl = extractRecordDeclaration(child) { types.append(typeDecl) }
            case "annotation_type_declaration":
                if let typeDecl = extractAnnotationTypeDeclaration(child) { types.append(typeDecl) }
            default:
                break
            }
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

    private func typeId(_ name: String) -> String { qualifiedName(name) }

    // MARK: - Modifiers

    private func extractModifiers(_ node: Node) -> ModifierInfo {
        var accessLevel: AccessLevel?
        var modifiers: [Modifier] = []
        var annotations: [String] = []

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "public":      accessLevel = .public
            case "private":     accessLevel = .private
            case "protected":   accessLevel = .protected
            case "static":      modifiers.append(.static)
            case "final":       modifiers.append(.final)
            case "abstract":    modifiers.append(.abstract)
            case "synchronized": modifiers.append(.synchronized)
            case "volatile":    modifiers.append(.volatile)
            case "transient":   modifiers.append(.transient)
            case "native":      modifiers.append(.native)
            case "strictfp":    modifiers.append(.strictfp)
            case "default":     modifiers.append(.default)
            case "marker_annotation", "annotation":
                annotations.append(text(child))
            default:
                break
            }
        }

        return ModifierInfo(accessLevel: accessLevel, modifiers: modifiers, annotations: annotations)
    }

    private func extractModifiersFromParent(_ node: Node) -> ModifierInfo {
        if let modifiersNode = node.firstChild(withType: "modifiers") {
            return extractModifiers(modifiersNode)
        }
        return ModifierInfo(accessLevel: nil, modifiers: [], annotations: [])
    }

    // MARK: - Class Declaration

    private mutating func extractClassDeclaration(_ node: Node) -> TypeDeclaration? {
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
                relationships.append(Relationship(kind: .inheritance, source: qualifiedTypeName, target: superType.name))
            }
        }

        if let interfacesNode = node.child(byFieldName: "interfaces") {
            for ifaceType in extractTypeList(interfacesNode) {
                inheritedTypes.append(ifaceType)
                relationships.append(Relationship(kind: .conformance, source: qualifiedTypeName, target: ifaceType.name))
            }
        }

        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []
        var enumCases: [EnumCase] = []

        if let bodyNode = node.child(byFieldName: "body") {
            extractClassBody(
                bodyNode, members: &members, nestedTypes: &nestedTypes, enumCases: &enumCases, parentQualifiedName: qualifiedTypeName
            )
        }

        return TypeDeclaration(
            id: typeId(name), name: name, qualifiedName: qualifiedTypeName, kind: .class,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            genericParameters: genericParams, inheritedTypes: inheritedTypes,
            members: members, enumCases: enumCases, nestedTypes: nestedTypes,
            annotations: modifierInfo.annotations, namespace: currentNamespace, location: nodeLoc
        )
    }

    // MARK: - Interface Declaration

    private mutating func extractInterfaceDeclaration(_ node: Node) -> TypeDeclaration? {
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

        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []
        var enumCases: [EnumCase] = []

        if let bodyNode = node.child(byFieldName: "body") {
            extractInterfaceBody(
                bodyNode, members: &members, nestedTypes: &nestedTypes, enumCases: &enumCases, parentQualifiedName: qualifiedTypeName
            )
        }

        return TypeDeclaration(
            id: typeId(name), name: name, qualifiedName: qualifiedTypeName, kind: .interface,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            genericParameters: genericParams, inheritedTypes: inheritedTypes,
            members: members, enumCases: enumCases, nestedTypes: nestedTypes,
            annotations: modifierInfo.annotations, namespace: currentNamespace, location: nodeLoc
        )
    }

    // MARK: - Enum Declaration

    private mutating func extractEnumDeclaration(_ node: Node) -> TypeDeclaration? {
        let modifierInfo = extractModifiersFromParent(node)
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)
        let nodeLoc = loc(node)

        var inheritedTypes: [TypeReference] = []
        if let interfacesNode = node.child(byFieldName: "interfaces") {
            for ifaceType in extractTypeList(interfacesNode) {
                inheritedTypes.append(ifaceType)
                relationships.append(Relationship(kind: .conformance, source: qualifiedTypeName, target: ifaceType.name))
            }
        }

        var enumCases: [EnumCase] = []
        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []

        if let bodyNode = node.child(byFieldName: "body") {
            extractEnumBody(bodyNode, enumCases: &enumCases, members: &members, nestedTypes: &nestedTypes, parentQualifiedName: qualifiedTypeName)
        }

        return TypeDeclaration(
            id: typeId(name), name: name, qualifiedName: qualifiedTypeName, kind: .enum,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            inheritedTypes: inheritedTypes, members: members, enumCases: enumCases,
            nestedTypes: nestedTypes, annotations: modifierInfo.annotations,
            namespace: currentNamespace, location: nodeLoc
        )
    }

    // MARK: - Record Declaration

    private mutating func extractRecordDeclaration(_ node: Node) -> TypeDeclaration? {
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
                relationships.append(Relationship(kind: .conformance, source: qualifiedTypeName, target: ifaceType.name))
            }
        }

        var members: [Member] = []
        if let paramsNode = node.child(byFieldName: "parameters") {
            for component in extractRecordComponents(paramsNode) {
                members.append(Member(
                    name: component.internalName, kind: .property,
                    accessLevel: .public, type: component.type, location: nodeLoc
                ))
            }
        }

        var nestedTypes: [TypeDeclaration] = []
        var enumCases: [EnumCase] = []
        if let bodyNode = node.child(byFieldName: "body") {
            extractClassBody(
                bodyNode, members: &members, nestedTypes: &nestedTypes, enumCases: &enumCases, parentQualifiedName: qualifiedTypeName
            )
        }

        return TypeDeclaration(
            id: typeId(name), name: name, qualifiedName: qualifiedTypeName, kind: .record,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            genericParameters: genericParams, inheritedTypes: inheritedTypes,
            members: members, enumCases: enumCases, nestedTypes: nestedTypes,
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

    private mutating func extractAnnotationTypeDeclaration(_ node: Node) -> TypeDeclaration? {
        let modifierInfo = extractModifiersFromParent(node)
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)
        let nodeLoc = loc(node)

        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []

        if let bodyNode = node.child(byFieldName: "body") {
            extractAnnotationTypeBody(bodyNode, members: &members, nestedTypes: &nestedTypes, parentQualifiedName: qualifiedTypeName)
        }

        return TypeDeclaration(
            id: typeId(name), name: name, qualifiedName: qualifiedTypeName, kind: .annotation,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            members: members, nestedTypes: nestedTypes,
            annotations: modifierInfo.annotations, namespace: currentNamespace, location: nodeLoc
        )
    }
}

// MARK: - Body & Member Extraction

extension JavaExtractor {

    private func buildPropertyMap(from existingMembers: [Member], node: Node) -> [String: String] {
        var knownProperties: [String: String] = [:]
        for member in existingMembers where member.kind == .property {
            if let typeName = member.type?.name { knownProperties[member.name] = typeName }
        }
        for child in node.children() where child.nodeType == "field_declaration" {
            for field in extractFieldDeclaration(child) where field.kind == .property {
                if let typeName = field.type?.name { knownProperties[field.name] = typeName }
            }
        }
        return knownProperties
    }

    private mutating func extractNestedTypeFromChild(_ child: Node, nodeType: String) -> TypeDeclaration? {
        switch nodeType {
        case "class_declaration":          return extractClassDeclaration(child)
        case "interface_declaration":      return extractInterfaceDeclaration(child)
        case "enum_declaration":           return extractEnumDeclaration(child)
        case "record_declaration":         return extractRecordDeclaration(child)
        case "annotation_type_declaration": return extractAnnotationTypeDeclaration(child)
        default:                            return nil
        }
    }

    private mutating func extractClassBody(
        _ node: Node,
        members: inout [Member],
        nestedTypes: inout [TypeDeclaration],
        enumCases: inout [EnumCase],
        parentQualifiedName: String
    ) {
        let knownProperties = buildPropertyMap(from: members, node: node)

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "method_declaration":
                if let member = extractMethodDeclaration(child, knownProperties: knownProperties) {
                    members.append(member)
                }
            case "constructor_declaration":
                if let member = extractConstructorDeclaration(child, knownProperties: knownProperties) {
                    members.append(member)
                }
            case "field_declaration":
                members.append(contentsOf: extractFieldDeclaration(child))
            case "class_declaration", "interface_declaration", "enum_declaration",
                 "record_declaration", "annotation_type_declaration":
                if let nested = extractNestedTypeFromChild(child, nodeType: nodeType) {
                    nestedTypes.append(nested)
                }
            case "static_initializer", "block", ";":
                break
            default:
                break
            }
        }
    }

    private mutating func extractInterfaceBody(
        _ node: Node,
        members: inout [Member],
        nestedTypes: inout [TypeDeclaration],
        enumCases: inout [EnumCase],
        parentQualifiedName: String
    ) {
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "method_declaration":
                if let member = extractMethodDeclaration(child) { members.append(member) }
            case "constant_declaration", "field_declaration":
                members.append(contentsOf: extractFieldDeclaration(child))
            case "class_declaration":
                if let nested = extractClassDeclaration(child) { nestedTypes.append(nested) }
            case "interface_declaration":
                if let nested = extractInterfaceDeclaration(child) { nestedTypes.append(nested) }
            case "enum_declaration":
                if let nested = extractEnumDeclaration(child) { nestedTypes.append(nested) }
            case "record_declaration":
                if let nested = extractRecordDeclaration(child) { nestedTypes.append(nested) }
            case "annotation_type_declaration":
                if let nested = extractAnnotationTypeDeclaration(child) { nestedTypes.append(nested) }
            default:
                break
            }
        }
    }

    private mutating func extractEnumBody(
        _ node: Node,
        enumCases: inout [EnumCase],
        members: inout [Member],
        nestedTypes: inout [TypeDeclaration],
        parentQualifiedName: String
    ) {
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "enum_constant":
                if let enumCase = extractEnumConstant(child) { enumCases.append(enumCase) }
            case "enum_body_declarations":
                extractClassBody(
                    child, members: &members, nestedTypes: &nestedTypes,
                    enumCases: &enumCases, parentQualifiedName: parentQualifiedName
                )
            case "method_declaration":
                if let member = extractMethodDeclaration(child) { members.append(member) }
            case "constructor_declaration":
                if let member = extractConstructorDeclaration(child) { members.append(member) }
            case "field_declaration":
                members.append(contentsOf: extractFieldDeclaration(child))
            case "class_declaration":
                if let nested = extractClassDeclaration(child) { nestedTypes.append(nested) }
            case "interface_declaration":
                if let nested = extractInterfaceDeclaration(child) { nestedTypes.append(nested) }
            default:
                break
            }
        }
    }

    private mutating func extractAnnotationTypeBody(
        _ node: Node,
        members: inout [Member],
        nestedTypes: inout [TypeDeclaration],
        parentQualifiedName: String
    ) {
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "annotation_type_element_declaration":
                if let member = extractAnnotationTypeElement(child) { members.append(member) }
            case "field_declaration", "constant_declaration":
                members.append(contentsOf: extractFieldDeclaration(child))
            case "class_declaration":
                if let nested = extractClassDeclaration(child) { nestedTypes.append(nested) }
            case "interface_declaration":
                if let nested = extractInterfaceDeclaration(child) { nestedTypes.append(nested) }
            case "enum_declaration":
                if let nested = extractEnumDeclaration(child) { nestedTypes.append(nested) }
            default:
                break
            }
        }
    }

    private func extractAnnotationTypeElement(_ node: Node) -> Member? {
        let modifierInfo = extractModifiersFromParent(node)
        let nodeLoc = loc(node)
        var returnType: TypeReference?
        var name = ""

        if let typeNode = node.child(byFieldName: "type") { returnType = extractTypeReference(typeNode) }
        if let nameNode = node.child(byFieldName: "name") { name = text(nameNode) }
        guard !name.isEmpty else { return nil }

        return Member(
            name: name, kind: .method,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            type: returnType, annotations: modifierInfo.annotations, location: nodeLoc
        )
    }

    // MARK: - Enum Constant

    private func extractEnumConstant(_ node: Node) -> EnumCase? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        guard !name.isEmpty else { return nil }
        let nodeLoc = loc(node)

        var arguments: [Parameter] = []
        if let argsNode = node.child(byFieldName: "arguments") {
            arguments = extractArgumentsAsParameters(argsNode)
        }

        return EnumCase(name: name, associatedValues: arguments, location: nodeLoc)
    }

    private func extractArgumentsAsParameters(_ node: Node) -> [Parameter] {
        return node.namedChildren().compactMap { child in
            let argText = text(child)
            return argText.isEmpty ? nil : Parameter(internalName: argText)
        }
    }

    // MARK: - Method Declaration

    private func extractMethodDeclaration(
        _ node: Node,
        knownProperties: [String: String] = [:]
    ) -> Member? {
        let modifierInfo = extractModifiersFromParent(node)
        let nodeLoc = loc(node)

        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        guard !name.isEmpty else { return nil }

        var returnType: TypeReference?
        if let typeNode = node.child(byFieldName: "type") {
            returnType = extractTypeReference(typeNode)
        }

        let genericParams = extractTypeParameters(from: node)
        var parameters: [Parameter] = []
        if let paramsNode = node.child(byFieldName: "parameters") {
            parameters = extractFormalParameters(paramsNode)
        }

        let callSites = extractCallSites(from: node.child(byFieldName: "body"),
                                         knownProperties: knownProperties)

        return Member(
            name: name, kind: .method,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            type: returnType, parameters: parameters, genericParameters: genericParams,
            annotations: modifierInfo.annotations, location: nodeLoc,
            callSites: callSites
        )
    }

    // MARK: - Constructor Declaration

    private func extractConstructorDeclaration(
        _ node: Node,
        knownProperties: [String: String] = [:]
    ) -> Member? {
        let modifierInfo = extractModifiersFromParent(node)
        let nodeLoc = loc(node)

        let name = node.child(byFieldName: "name").map { text($0) } ?? ""
        let genericParams = extractTypeParameters(from: node)
        var parameters: [Parameter] = []
        if let paramsNode = node.child(byFieldName: "parameters") {
            parameters = extractFormalParameters(paramsNode)
        }

        let callSites = extractCallSites(from: node.child(byFieldName: "body"),
                                         knownProperties: knownProperties)

        return Member(
            name: name, kind: .initializer,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            parameters: parameters, genericParameters: genericParams,
            annotations: modifierInfo.annotations, location: nodeLoc,
            callSites: callSites
        )
    }

    // MARK: - Field Declaration

    private func extractFieldDeclaration(_ node: Node) -> [Member] {
        let modifierInfo = extractModifiersFromParent(node)
        let nodeLoc = loc(node)

        var fieldType: TypeReference?
        if let typeNode = node.child(byFieldName: "type") {
            fieldType = extractTypeReference(typeNode)
        }

        // Collect all variable_declarator children (handles: int x, y, z;)
        let declarators = node.allChildren(withType: "variable_declarator")
        if !declarators.isEmpty {
            return declarators.compactMap {
                extractVariableDeclarator($0, fieldType: fieldType, modifierInfo: modifierInfo, loc: nodeLoc)
            }
        }

        // Fallback: try declarator field name
        if let declaratorNode = node.child(byFieldName: "declarator") {
            if let member = extractVariableDeclarator(
                declaratorNode, fieldType: fieldType, modifierInfo: modifierInfo, loc: nodeLoc
            ) {
                return [member]
            }
        }
        return []
    }

    private func extractVariableDeclarator(
        _ node: Node,
        fieldType: TypeReference?,
        modifierInfo: ModifierInfo,
        loc: SourceLocation
    ) -> Member? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        guard !name.isEmpty else { return nil }

        var actualType = fieldType
        if let dimensionsNode = node.child(byFieldName: "dimensions") {
            let dimText = text(dimensionsNode)
            let bracketPairs = dimText.components(separatedBy: "[]").count - 1
            if bracketPairs > 0, let arrayFieldType = actualType {
                actualType = TypeReference(
                    name: arrayFieldType.name, genericArguments: arrayFieldType.genericArguments,
                    isOptional: arrayFieldType.isOptional, isArray: true
                )
            }
        }

        return Member(
            name: name, kind: .property,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            type: actualType, annotations: modifierInfo.annotations, location: loc
        )
    }

    // MARK: - Formal Parameters

    private func extractFormalParameters(_ node: Node) -> [Parameter] {
        var params: [Parameter] = []
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "formal_parameter":
                if let param = extractFormalParameter(child) { params.append(param) }
            case "spread_parameter":
                if let param = extractSpreadParameter(child) { params.append(param) }
            case "receiver_parameter":
                break // Skip 'this' parameter
            default:
                break
            }
        }
        return params
    }

    private func extractFormalParameter(_ node: Node) -> Parameter? {
        var paramType: TypeReference?
        var name = ""
        var paramModifiers: [Modifier] = []

        if let modNode = node.firstChild(withType: "modifiers") {
            paramModifiers = extractModifiers(modNode).modifiers
        }

        if let typeNode = node.child(byFieldName: "type") { paramType = extractTypeReference(typeNode) }
        if let nameNode = node.child(byFieldName: "name") { name = text(nameNode) }
        guard !name.isEmpty else { return nil }

        if let dimensionsNode = node.child(byFieldName: "dimensions") {
            let dimText = text(dimensionsNode)
            if !dimText.isEmpty, let parameterType = paramType {
                paramType = TypeReference(
                    name: parameterType.name, genericArguments: parameterType.genericArguments,
                    isOptional: parameterType.isOptional, isArray: true
                )
            }
        }

        return Parameter(internalName: name, type: paramType, modifiers: paramModifiers)
    }

    private func extractSpreadParameter(_ node: Node) -> Parameter? {
        var paramType: TypeReference?
        var name = ""
        if let typeNode = node.child(byFieldName: "type") { paramType = extractTypeReference(typeNode) }
        if let nameNode = node.child(byFieldName: "name") { name = text(nameNode) }
        // Fallback: last named child is usually the name in varargs
        if name.isEmpty, let lastNamed = node.namedChildren().last { name = text(lastNamed) }
        guard !name.isEmpty else { return nil }
        return Parameter(internalName: name, type: paramType, isVariadic: true)
    }
}

// MARK: - Type References, Generics & Call Sites

extension JavaExtractor {

    /// Matches Java `method_invocation` nodes.
    ///
    /// Handles:
    /// - `receiver.method(args)` — `object` field is an `identifier`.
    /// - `this.receiver.method(args)` — `object` field is a `field_access` whose own
    ///   `object` is `this`.
    func resolveCallSite(_ node: Node, knownProperties: [String: String]) -> CallSite? {
        guard node.nodeType == "method_invocation",
              let nameNode = node.child(byFieldName: "name"),
              let objectNode = node.child(byFieldName: "object")
        else { return nil }

        let methodName = text(nameNode)
        var receiverVarName: String?

        if objectNode.nodeType == "identifier" {
            receiverVarName = text(objectNode)
        } else if objectNode.nodeType == "field_access",
                  objectNode.child(byFieldName: "object")?.nodeType == "this",
                  let fieldNode = objectNode.child(byFieldName: "field") {
            receiverVarName = text(fieldNode)
        }

        guard let varName = receiverVarName,
              let receiverType = knownProperties[varName]
        else { return nil }

        return CallSite(receiverType: receiverType, methodName: methodName, location: loc(node))
    }

    // MARK: - Type References

    private func extractTypeReference(_ node: Node) -> TypeReference? {
        guard let nodeType = node.nodeType else { return nil }

        switch nodeType {
        case "type_identifier", "integral_type", "floating_point_type",
             "scoped_type_identifier":
            return TypeReference(name: text(node))
        case "void_type":
            return TypeReference(name: "void")
        case "boolean_type":
            return TypeReference(name: "boolean")
        case "generic_type":
            return extractGenericTypeReference(node)
        case "array_type":
            return extractArrayTypeReference(node)
        case "wildcard":
            return extractWildcard(node)
        case "annotated_type":
            return extractAnnotatedTypeReference(node)
        case "dimensions":
            return nil
        default:
            let typeName = text(node)
            return typeName.isEmpty ? nil : TypeReference(name: typeName)
        }
    }

    private func extractGenericTypeReference(_ node: Node) -> TypeReference {
        var name = ""
        var genericArgs: [TypeReference] = []
        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            switch childType {
            case "type_identifier", "scoped_type_identifier":
                name = text(child)
            case "type_arguments":
                genericArgs = extractTypeArguments(child)
            default:
                break
            }
        }
        return TypeReference(name: name, genericArguments: genericArgs)
    }

    private func extractArrayTypeReference(_ node: Node) -> TypeReference {
        if let elementNode = node.child(byFieldName: "element"),
           let elementRef = extractTypeReference(elementNode) {
            return TypeReference(
                name: elementRef.name, genericArguments: elementRef.genericArguments,
                isOptional: elementRef.isOptional, isArray: true
            )
        }
        let trimmed = text(node).replacingOccurrences(of: "[]", with: "")
        return TypeReference(name: trimmed, isArray: true)
    }

    private func extractAnnotatedTypeReference(_ node: Node) -> TypeReference? {
        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            if childType != "marker_annotation" && childType != "annotation" {
                if let ref = extractTypeReference(child) { return ref }
            }
        }
        return nil
    }

    private func extractWildcard(_ node: Node) -> TypeReference {
        var wildcardName = "?"
        var constraints: [TypeReference] = []

        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            if childType == "extends" || childType == "super" { continue }
            if let ref = extractTypeReference(child), ref.name != "?" {
                constraints.append(ref)
            }
        }

        let fullText = text(node)
        if fullText.contains("extends") || fullText.contains("super") {
            wildcardName = fullText
        }
        return TypeReference(name: wildcardName, genericArguments: constraints)
    }

    private func extractTypeArguments(_ node: Node) -> [TypeReference] {
        return node.namedChildren().compactMap { extractTypeReference($0) }
    }

    // MARK: - Type Parameters (Generics)

    private func extractTypeParameters(from node: Node) -> [GenericParameter] {
        if let typeParamsNode = node.child(byFieldName: "type_parameters") {
            return extractTypeParameterList(typeParamsNode)
        }
        if let typeParamsNode = node.firstChild(withType: "type_parameters") {
            return extractTypeParameterList(typeParamsNode)
        }
        return []
    }

    private func extractTypeParameterList(_ node: Node) -> [GenericParameter] {
        return node.allChildren(withType: "type_parameter").map { extractTypeParameter($0) }
    }

    private func extractTypeParameter(_ node: Node) -> GenericParameter {
        var name = ""
        var constraints: [GenericConstraint] = []

        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            switch childType {
            case "type_identifier", "identifier":
                if name.isEmpty { name = text(child) }
            case "type_bound":
                constraints = extractTypeBound(child)
            default:
                break
            }
        }
        return GenericParameter(name: name, constraints: constraints)
    }

    private func extractTypeBound(_ node: Node) -> [GenericConstraint] {
        var constraints: [GenericConstraint] = []
        var isFirst = true
        for child in node.namedChildren() {
            if let ref = extractTypeReference(child) {
                let kind: GenericConstraint.Kind = isFirst ? .superclass : .conformance
                constraints.append(GenericConstraint(kind: kind, type: ref))
                isFirst = false
            }
        }
        return constraints
    }

    // MARK: - Superclass / Interface Lists

    private func extractSuperclassTypes(_ node: Node) -> [TypeReference] {
        return node.namedChildren().compactMap { extractTypeReference($0) }
    }

    private func extractTypeList(_ node: Node) -> [TypeReference] {
        var refs: [TypeReference] = []
        for child in node.namedChildren() {
            if child.nodeType == "type_list" {
                refs.append(contentsOf: extractTypeList(child))
            } else if let ref = extractTypeReference(child) {
                refs.append(ref)
            }
        }
        return refs
    }
}
