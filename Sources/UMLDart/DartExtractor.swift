import Foundation
import UMLCore
import UMLTreeSitter

struct DartExtractor: TreeSitterExtracting {
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
        return buildArtifact(language: .dart)
    }
}

// MARK: - Program & Top-Level Extraction

extension DartExtractor {

    @discardableResult
    private mutating func processTopLevelTypeNode(_ child: Node, nodeType: String) -> Bool {
        switch nodeType {
        case "class_definition":
            if let typeDecl = extractClassDefinition(child) { types.append(typeDecl) }
        case "enum_declaration":
            if let typeDecl = extractEnumDeclaration(child) { types.append(typeDecl) }
        case "mixin_declaration":
            if let typeDecl = extractMixinDeclaration(child) { types.append(typeDecl) }
        case "extension_declaration":
            if let typeDecl = extractExtensionDeclaration(child) { types.append(typeDecl) }
        case "extension_type_declaration":
            if let typeDecl = extractExtensionTypeDeclaration(child) { types.append(typeDecl) }
        case "function_signature":
            if let function = extractFunctionSignature(child, isTopLevel: true) {
                freestandingFunctions.append(function)
            }
        default:
            return false
        }
        return true
    }

    mutating func walkSourceFile(_ node: Node) {
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "library_name":
                currentNamespace = extractLibraryName(child)
            case "declaration":
                extractTopLevelChildren(child)
            case "import_or_export", "part_directive", "part_of_directive":
                break
            default:
                if !processTopLevelTypeNode(child, nodeType: nodeType) {
                    extractTopLevelChildren(child)
                }
            }
        }
    }

    /// Some top-level constructs may be wrapped in container nodes.
    private mutating func extractTopLevelChildren(_ node: Node) {
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            processTopLevelTypeNode(child, nodeType: nodeType)
        }
    }

    // MARK: - Library Name

    private func extractLibraryName(_ node: Node) -> String? {
        let children = node.namedChildren()
        return children.first.map { text($0) }
    }
}

// MARK: - Type Declarations

extension DartExtractor {

    private mutating func extractClassDefinition(_ node: Node) -> TypeDeclaration? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        let typeId = qualifiedName(name)
        let nodeLoc = loc(node)
        let modifiers = extractClassModifiers(node)
        let genericParams = extractTypeParameters(from: node)
        var inheritedTypes: [TypeReference] = []

        // Superclass (extends).
        if let superclassNode = node.child(byFieldName: "superclass") {
            for ref in extractSuperclassTypes(superclassNode) {
                inheritedTypes.append(ref)
                let label = ref.genericArguments.isEmpty ? nil
                    : "<" + ref.genericArguments.map(\.name).joined(separator: ", ") + ">"
                relationships.append(Relationship(
                    kind: .inheritance, source: typeId, target: ref.name, label: label))
            }
        }

        // Mixins (with).
        for child in node.children() where child.nodeType == "mixins" {
            for ref in extractTypeList(child) {
                inheritedTypes.append(ref)
                relationships.append(Relationship(
                    kind: .inheritance, source: typeId, target: ref.name))
            }
        }

        // Interfaces (implements).
        if let interfacesNode = node.child(byFieldName: "interfaces") {
            for ref in extractTypeList(interfacesNode) {
                inheritedTypes.append(ref)
                relationships.append(Relationship(
                    kind: .conformance, source: typeId, target: ref.name))
            }
        }

        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []

        if let bodyNode = node.child(byFieldName: "body") {
            extractClassBody(bodyNode, members: &members, nestedTypes: &nestedTypes, parentName: name)
        }

        return TypeDeclaration(
            id: typeId, name: name, qualifiedName: typeId, kind: .class,
            accessLevel: accessLevel(for: name),
            modifiers: modifiers,
            genericParameters: genericParams, inheritedTypes: inheritedTypes,
            members: members, nestedTypes: nestedTypes,
            namespace: currentNamespace, location: nodeLoc
        )
    }

    // MARK: - Enum Declaration

    private mutating func extractEnumDeclaration(_ node: Node) -> TypeDeclaration? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        let typeId = qualifiedName(name)
        let nodeLoc = loc(node)
        var inheritedTypes: [TypeReference] = []

        // Mixins.
        for child in node.children() where child.nodeType == "mixins" {
            for ref in extractTypeList(child) {
                inheritedTypes.append(ref)
                relationships.append(Relationship(
                    kind: .inheritance, source: typeId, target: ref.name))
            }
        }

        // Interfaces.
        for child in node.children() where child.nodeType == "interfaces" {
            for ref in extractTypeList(child) {
                inheritedTypes.append(ref)
                relationships.append(Relationship(
                    kind: .conformance, source: typeId, target: ref.name))
            }
        }

        var enumCases: [EnumCase] = []
        var members: [Member] = []

        if let bodyNode = node.child(byFieldName: "body") {
            extractEnumBody(bodyNode, enumCases: &enumCases, members: &members, parentName: name)
        }

        return TypeDeclaration(
            id: typeId, name: name, qualifiedName: typeId, kind: .enum,
            accessLevel: accessLevel(for: name),
            inheritedTypes: inheritedTypes,
            members: members, enumCases: enumCases,
            namespace: currentNamespace, location: nodeLoc
        )
    }

    // MARK: - Mixin Declaration

    private mutating func extractMixinDeclaration(_ node: Node) -> TypeDeclaration? {
        // Mixin: optional(metadata) optional(base) 'mixin' identifier
        // optional(type_parameters) optional('on' type_list)
        // optional(interfaces) class_body
        var name = ""
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "identifier" && name.isEmpty {
                name = text(child)
            }
        }
        guard !name.isEmpty else { return nil }
        let typeId = qualifiedName(name)
        let nodeLoc = loc(node)
        let genericParams = extractTypeParametersFromChildren(node)
        var inheritedTypes: [TypeReference] = []

        // 'on' constraint types.
        for child in node.children() {
            if child.nodeType == "type_not_void_list" || child.nodeType == "_type_not_void_list" {
                for ref in extractTypeListFromChildren(child) {
                    inheritedTypes.append(ref)
                    relationships.append(Relationship(
                        kind: .inheritance, source: typeId, target: ref.name))
                }
            }
        }

        // Interfaces.
        for child in node.children() where child.nodeType == "interfaces" {
            for ref in extractTypeList(child) {
                inheritedTypes.append(ref)
                relationships.append(Relationship(
                    kind: .conformance, source: typeId, target: ref.name))
            }
        }

        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []

        // The body is a class_body node.
        for child in node.children() where child.nodeType == "class_body" {
            extractClassBody(child, members: &members, nestedTypes: &nestedTypes, parentName: name)
        }

        return TypeDeclaration(
            id: typeId, name: name, qualifiedName: typeId, kind: .mixin,
            accessLevel: accessLevel(for: name),
            genericParameters: genericParams, inheritedTypes: inheritedTypes,
            members: members, nestedTypes: nestedTypes,
            namespace: currentNamespace, location: nodeLoc
        )
    }

    // MARK: - Extension Declaration

    private mutating func extractExtensionDeclaration(_ node: Node) -> TypeDeclaration? {
        let name = node.child(byFieldName: "name").map { text($0) }
        let extendedType = node.child(byFieldName: "class").map { text($0) }
        let nodeLoc = loc(node)

        let displayName = name ?? (extendedType.map { "\($0)Extension" }) ?? "Extension"

        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []

        if let bodyNode = node.child(byFieldName: "body") {
            extractClassBody(bodyNode, members: &members, nestedTypes: &nestedTypes, parentName: displayName)
        }

        return TypeDeclaration(
            id: qualifiedName(displayName), name: displayName, qualifiedName: qualifiedName(displayName),
            kind: .extension,
            members: members, nestedTypes: nestedTypes,
            extensionOf: extendedType,
            namespace: currentNamespace, location: nodeLoc
        )
    }

    // MARK: - Extension Type Declaration

    private mutating func extractExtensionTypeDeclaration(_ node: Node) -> TypeDeclaration? {
        var name = ""
        for child in node.children() {
            if child.nodeType == "identifier" && name.isEmpty {
                name = text(child)
            }
        }
        guard !name.isEmpty else { return nil }
        let typeId = qualifiedName(name)
        let nodeLoc = loc(node)
        var inheritedTypes: [TypeReference] = []

        for child in node.children() where child.nodeType == "interfaces" {
            for ref in extractTypeList(child) {
                inheritedTypes.append(ref)
                relationships.append(Relationship(
                    kind: .conformance, source: typeId, target: ref.name))
            }
        }

        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []

        for child in node.children() {
            if child.nodeType == "extension_body" || child.nodeType == "class_body" {
                extractClassBody(child, members: &members, nestedTypes: &nestedTypes, parentName: name)
            }
        }

        return TypeDeclaration(
            id: typeId, name: name, qualifiedName: typeId, kind: .class,
            accessLevel: accessLevel(for: name),
            inheritedTypes: inheritedTypes,
            members: members, nestedTypes: nestedTypes,
            namespace: currentNamespace, location: nodeLoc
        )
    }
}

// MARK: - Body Extraction & Member Signatures

extension DartExtractor {

    @discardableResult
    private mutating func processClassMemberNode(
        _ child: Node,
        nodeType: String,
        members: inout [Member],
        nestedTypes: inout [TypeDeclaration],
        parentName: String
    ) -> Bool {
        switch nodeType {
        case "method_signature":
            if let member = extractMethodSignature(child) { members.append(member) }
        case "function_signature":
            if let member = extractFunctionSignature(child, isTopLevel: false) { members.append(member) }
        case "constructor_signature", "constant_constructor_signature":
            if let member = extractConstructorSignature(child, parentName: parentName) { members.append(member) }
        case "factory_constructor_signature", "redirecting_factory_constructor_signature":
            if let member = extractFactoryConstructorSignature(child) { members.append(member) }
        case "getter_signature":
            if let member = extractGetterSignature(child) { members.append(member) }
        case "setter_signature":
            if let member = extractSetterSignature(child) { members.append(member) }
        case "operator_signature":
            if let member = extractOperatorSignature(child) { members.append(member) }
        case "static_final_declaration_list", "initialized_identifier_list":
            members.append(contentsOf: extractFieldDeclarations(child))
        case "class_definition":
            if let typeDecl = extractClassDefinition(child) { nestedTypes.append(typeDecl) }
        case "enum_declaration":
            if let typeDecl = extractEnumDeclaration(child) { nestedTypes.append(typeDecl) }
        case "mixin_declaration":
            if let typeDecl = extractMixinDeclaration(child) { nestedTypes.append(typeDecl) }
        default:
            return false
        }
        return true
    }

    private mutating func extractClassBody(
        _ node: Node,
        members: inout [Member],
        nestedTypes: inout [TypeDeclaration],
        parentName: String
    ) {
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "declaration" {
                extractClassMemberDeclaration(
                    child, members: &members, nestedTypes: &nestedTypes, parentName: parentName
                )
            } else {
                processClassMemberNode(
                    child, nodeType: nodeType, members: &members,
                    nestedTypes: &nestedTypes, parentName: parentName
                )
            }
        }
    }

    /// Handles `declaration` nodes inside class bodies.
    private mutating func extractClassMemberDeclaration(
        _ node: Node,
        members: inout [Member],
        nestedTypes: inout [TypeDeclaration],
        parentName: String
    ) {
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if !processClassMemberNode(
                child, nodeType: nodeType, members: &members,
                nestedTypes: &nestedTypes, parentName: parentName
            ) {
                if let fields = extractFieldFromDeclarationChild(child, parentNodeType: nodeType) {
                    members.append(contentsOf: fields)
                }
            }
        }
    }

    // MARK: - Enum Body

    private mutating func extractEnumBody(
        _ node: Node,
        enumCases: inout [EnumCase],
        members: inout [Member],
        parentName: String
    ) {
        var ignored: [TypeDeclaration] = []
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "enum_constant":
                if let enumCase = extractEnumConstant(child) { enumCases.append(enumCase) }
            case "declaration":
                extractClassMemberDeclaration(
                    child, members: &members, nestedTypes: &ignored, parentName: parentName
                )
            default:
                processClassMemberNode(
                    child, nodeType: nodeType, members: &members,
                    nestedTypes: &ignored, parentName: parentName
                )
            }
        }
    }

    private func extractEnumConstant(_ node: Node) -> EnumCase? {
        var name = ""
        for child in node.children() where child.nodeType == "identifier" {
            name = text(child)
            break
        }
        guard !name.isEmpty else { return nil }
        return EnumCase(name: name, location: loc(node))
    }

    // MARK: - Method/Function Signatures

    private func extractMethodSignature(_ node: Node) -> Member? {
        // method_signature can wrap function_signature with optional 'static' prefix.
        let isStatic = node.hasAnonymousChild("static", in: context)
        var returnType: TypeReference?
        var name = ""
        var parameters: [Parameter] = []
        var genericParams: [GenericParameter] = []

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "function_signature":
                let inner = extractFunctionSignatureInner(child)
                returnType = inner.returnType
                name = inner.name
                parameters = inner.parameters
                genericParams = inner.genericParameters
            case "constructor_signature":
                if let member = extractConstructorSignature(child, parentName: "") {
                    return Member(
                        name: member.name, kind: member.kind,
                        modifiers: isStatic ? member.modifiers + [.static] : member.modifiers,
                        type: member.type, parameters: member.parameters, location: loc(node)
                    )
                }
            default:
                break
            }
        }

        guard !name.isEmpty else { return nil }
        var modifiers: [Modifier] = []
        if isStatic { modifiers.append(.static) }
        if node.hasAnonymousChild("abstract", in: context) { modifiers.append(.abstract) }

        return Member(
            name: name, kind: .method,
            accessLevel: accessLevel(for: name),
            modifiers: modifiers,
            type: returnType, parameters: parameters,
            genericParameters: genericParams,
            location: loc(node)
        )
    }

    private func extractFunctionSignature(_ node: Node, isTopLevel: Bool) -> Member? {
        let inner = extractFunctionSignatureInner(node)
        guard !inner.name.isEmpty else { return nil }

        var modifiers: [Modifier] = []
        if node.hasAnonymousChild("static", in: context) { modifiers.append(.static) }
        if node.hasAnonymousChild("external", in: context) { modifiers.append(.external) }

        return Member(
            name: inner.name, kind: .method,
            accessLevel: accessLevel(for: inner.name),
            modifiers: modifiers,
            type: inner.returnType, parameters: inner.parameters,
            genericParameters: inner.genericParameters,
            location: loc(node)
        )
    }

    private struct FunctionSignatureInfo {
        var returnType: TypeReference?
        var name: String = ""
        var parameters: [Parameter] = []
        var genericParameters: [GenericParameter] = []
    }

    private func extractFunctionSignatureInner(_ node: Node) -> FunctionSignatureInfo {
        var info = FunctionSignatureInfo()

        if let nameNode = node.child(byFieldName: "name") {
            info.name = text(nameNode)
        }

        // Collect parts.
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "identifier":
                if info.name.isEmpty { info.name = text(child) }
            case "type_parameters":
                info.genericParameters = extractTypeParameterList(child)
            case "formal_parameter_list":
                info.parameters = extractFormalParameterList(child)
            case "type_identifier", "void_type", "function_type":
                if info.returnType == nil {
                    info.returnType = extractTypeReference(child)
                }
            default:
                // Try to extract a return type from typed nodes.
                if info.returnType == nil, let ref = extractTypeReference(child) {
                    info.returnType = ref
                }
            }
        }

        return info
    }

    // MARK: - Constructor

    private func extractConstructorSignature(_ node: Node, parentName: String) -> Member? {
        var name = parentName
        var parameters: [Parameter] = []

        // Named constructors: ClassName.name
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "identifier":
                let childText = text(child)
                if childText != parentName && !childText.isEmpty {
                    name = childText
                }
            case "formal_parameter_list":
                parameters = extractFormalParameterList(child)
            default:
                break
            }
        }

        var modifiers: [Modifier] = []
        if node.hasAnonymousChild("const", in: context) { modifiers.append(.const) }

        return Member(
            name: name, kind: .initializer,
            modifiers: modifiers,
            parameters: parameters,
            location: loc(node)
        )
    }

    private func extractFactoryConstructorSignature(_ node: Node) -> Member? {
        var name = ""
        var parameters: [Parameter] = []

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "identifier":
                if name.isEmpty { name = text(child) }
            case "formal_parameter_list":
                parameters = extractFormalParameterList(child)
            default:
                break
            }
        }

        return Member(
            name: name, kind: .initializer,
            modifiers: [.factory],
            parameters: parameters,
            location: loc(node)
        )
    }

    // MARK: - Getter/Setter/Operator

    private func extractGetterSignature(_ node: Node) -> Member? {
        var returnType: TypeReference?
        var name = ""

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "identifier":
                name = text(child)
            case "type_identifier", "void_type":
                returnType = extractTypeReference(child)
            default:
                break
            }
        }
        guard !name.isEmpty else { return nil }

        var modifiers: [Modifier] = []
        if node.hasAnonymousChild("static", in: context) { modifiers.append(.static) }

        return Member(
            name: name, kind: .property,
            accessLevel: accessLevel(for: name),
            modifiers: modifiers,
            type: returnType, isComputed: true,
            location: loc(node)
        )
    }

    private func extractSetterSignature(_ node: Node) -> Member? {
        var name = ""
        var paramType: TypeReference?

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "identifier":
                name = text(child)
            case "formal_parameter_list":
                let params = extractFormalParameterList(child)
                paramType = params.first?.type
            default:
                break
            }
        }
        guard !name.isEmpty else { return nil }

        var modifiers: [Modifier] = []
        if node.hasAnonymousChild("static", in: context) { modifiers.append(.static) }

        return Member(
            name: name, kind: .property,
            accessLevel: accessLevel(for: name),
            modifiers: modifiers,
            type: paramType, isComputed: true,
            location: loc(node)
        )
    }

    private func extractOperatorSignature(_ node: Node) -> Member? {
        Member(name: "operator", kind: .method, location: loc(node))
    }

    // MARK: - Field Declarations

    private func makeFieldMember(
        name: String, type: TypeReference?,
        isStatic: Bool, isLate: Bool, isConst: Bool, isFinal: Bool,
        location: SourceLocation
    ) -> Member {
        var modifiers: [Modifier] = []
        if isStatic { modifiers.append(.static) }
        if isLate { modifiers.append(.late) }
        if isConst { modifiers.append(.const) }
        if isFinal { modifiers.append(.final) }
        return Member(
            name: name, kind: .property,
            accessLevel: accessLevel(for: name),
            modifiers: modifiers, type: type, location: location
        )
    }

    private func extractFieldDeclarations(_ node: Node) -> [Member] {
        var members: [Member] = []
        let isStatic = node.hasAnonymousChild("static", in: context)
        let isLate = node.hasAnonymousChild("late", in: context)
        let isConst = node.nodeType == "static_final_declaration_list" ||
                      node.hasAnonymousChild("const", in: context) ||
                      node.hasAnonymousChild("final", in: context)

        var fieldType: TypeReference?
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "type_identifier", "generic_type", "function_type":
                if fieldType == nil { fieldType = extractTypeReference(child) }
            case "initialized_identifier":
                let varName = extractIdentifierName(child)
                guard !varName.isEmpty else { continue }
                members.append(makeFieldMember(
                    name: varName, type: fieldType,
                    isStatic: isStatic, isLate: isLate, isConst: isConst, isFinal: false,
                    location: loc(child)
                ))
            case "static_final_declaration":
                let varName = extractIdentifierName(child)
                guard !varName.isEmpty else { continue }
                members.append(makeFieldMember(
                    name: varName, type: fieldType,
                    isStatic: true, isLate: false, isConst: isConst, isFinal: true,
                    location: loc(child)
                ))
            case "identifier":
                let varName = text(child)
                guard !varName.isEmpty, !varName.hasPrefix("var"), !varName.hasPrefix("final") else { continue }
                if fieldType == nil {
                    fieldType = TypeReference(name: varName)
                } else {
                    members.append(makeFieldMember(
                        name: varName, type: fieldType,
                        isStatic: isStatic, isLate: isLate, isConst: false, isFinal: false,
                        location: loc(child)
                    ))
                }
            default:
                break
            }
        }
        return members
    }

    /// Attempt to extract fields from arbitrary child nodes of a declaration.
    private func extractFieldFromDeclarationChild(_ child: Node, parentNodeType: String) -> [Member]? {
        guard let nodeType = child.nodeType else { return nil }
        switch nodeType {
        case "static_final_declaration_list", "initialized_identifier_list":
            return extractFieldDeclarations(child)
        default:
            return nil
        }
    }

    private func extractIdentifierName(_ node: Node) -> String {
        for child in node.children() where child.nodeType == "identifier" {
            return text(child)
        }
        return ""
    }
}

// MARK: - Parameters, Types & Utilities

extension DartExtractor {

    private func extractFormalParameterList(_ node: Node) -> [Parameter] {
        var params: [Parameter] = []
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "formal_parameter", "normal_formal_parameter":
                if let parameter = extractFormalParameter(child) { params.append(parameter) }
            case "default_formal_parameter":
                if let parameter = extractDefaultFormalParameter(child) { params.append(parameter) }
            case "optional_positional_formal_parameters", "optional_named_formal_parameters":
                for innerChild in child.children() {
                    if let childType = innerChild.nodeType,
                       childType == "default_formal_parameter" || childType == "formal_parameter" || childType == "normal_formal_parameter" {
                        if let parameter = extractDefaultFormalParameter(innerChild) ?? extractFormalParameter(innerChild) {
                            params.append(parameter)
                        }
                    }
                }
            default:
                break
            }
        }
        return params
    }

    private func extractFormalParameter(_ node: Node) -> Parameter? {
        var paramType: TypeReference?
        var name = ""
        var modifiers: [Modifier] = []

        // Check for field formal parameter (this.name).
        let fullText = text(node)
        if fullText.contains("this.") {
            let parts = fullText.components(separatedBy: "this.")
            if parts.count >= 2 {
                let afterThis = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let paramName = afterThis
                    .components(separatedBy: CharacterSet.alphanumerics.inverted).first ?? afterThis
                return Parameter(internalName: paramName, type: nil)
            }
        }

        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            switch childType {
            case "identifier":
                let childText = text(child)
                if paramType == nil && name.isEmpty {
                    // Could be either the type or the name. If there's only one identifier, it's the name.
                    name = childText
                } else if !name.isEmpty && paramType == nil {
                    // Previous identifier was the type; this one is the name.
                    paramType = TypeReference(name: name)
                    name = childText
                }
            case "type_identifier", "generic_type", "function_type", "void_type":
                paramType = extractTypeReference(child)
            case "final_builtin":
                modifiers.append(.final)
            case "covariant":
                modifiers.append(.covariant)
            case "required":
                modifiers.append(.required)
            default:
                if paramType == nil, let ref = extractTypeReference(child) {
                    paramType = ref
                }
            }
        }

        guard !name.isEmpty else { return nil }
        return Parameter(internalName: name, type: paramType, modifiers: modifiers)
    }

    private func extractDefaultFormalParameter(_ node: Node) -> Parameter? {
        // default_formal_parameter wraps a normal_formal_parameter or formal_parameter with a default value.
        for child in node.children() {
            if child.nodeType == "formal_parameter" || child.nodeType == "normal_formal_parameter" {
                return extractFormalParameter(child)
            }
        }
        return extractFormalParameter(node)
    }

    // MARK: - Type References

    private func extractTypeReference(_ node: Node) -> TypeReference? {
        guard let nodeType = node.nodeType else { return nil }
        switch nodeType {
        case "type_identifier", "identifier":
            let name = text(node)
            let isOptional = node.parent?.nodeType == "nullable_type"
            return TypeReference(name: name, isOptional: isOptional)
        case "nullable_type":
            for child in node.namedChildren() {
                if var ref = extractTypeReference(child) {
                    return TypeReference(
                        name: ref.name, genericArguments: ref.genericArguments,
                        isOptional: true, isArray: ref.isArray
                    )
                }
            }
            return nil
        case "generic_type", "type_arguments":
            return extractGenericType(node)
        case "void_type":
            return TypeReference(name: "void")
        case "function_type":
            return TypeReference(name: text(node))
        case "inferred_type":
            return TypeReference(name: "var")
        default:
            let typeText = text(node).trimmingCharacters(in: .whitespacesAndNewlines)
            return typeText.isEmpty ? nil : TypeReference(name: typeText)
        }
    }

    private func extractGenericType(_ node: Node) -> TypeReference? {
        var name = ""
        var genericArgs: [TypeReference] = []

        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            switch childType {
            case "type_identifier", "identifier":
                if name.isEmpty { name = text(child) }
            case "type_arguments":
                genericArgs = child.namedChildren().compactMap { extractTypeReference($0) }
            default:
                break
            }
        }

        guard !name.isEmpty else { return nil }
        let isArray = name == "List"
        return TypeReference(name: name, genericArguments: genericArgs, isArray: isArray)
    }

    // MARK: - Type Parameters (Generics)

    private func extractTypeParameters(from node: Node) -> [GenericParameter] {
        if let typeParamsNode = node.child(byFieldName: "type_parameters") {
            return extractTypeParameterList(typeParamsNode)
        }
        return extractTypeParametersFromChildren(node)
    }

    private func extractTypeParametersFromChildren(_ node: Node) -> [GenericParameter] {
        for child in node.children() where child.nodeType == "type_parameters" {
            return extractTypeParameterList(child)
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
                if name.isEmpty { name = text(child) } else {
                    constraints.append(GenericConstraint(
                        kind: .superclass,
                        type: TypeReference(name: text(child))
                    ))
                }
            default:
                break
            }
        }
        return GenericParameter(name: name, constraints: constraints)
    }

    // MARK: - Superclass / Type Lists

    private func extractSuperclassTypes(_ node: Node) -> [TypeReference] {
        // superclass: 'extends' type optional(mixins) | mixins
        //
        // When the grammar emits `type_identifier` and `type_arguments` as
        // siblings (instead of wrapping them in a `generic_type` node), combine
        // them into a single TypeReference so we avoid spurious edges to
        // generic-argument types.
        var refs: [TypeReference] = []
        var pendingName: String?

        for child in node.namedChildren() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "mixins" { continue }

            if nodeType == "type_identifier" || nodeType == "identifier" {
                // Flush any previously pending simple name.
                if let name = pendingName {
                    refs.append(TypeReference(name: name))
                }
                pendingName = text(child)
            } else if nodeType == "type_arguments", let name = pendingName {
                let genericArgs = child.namedChildren().compactMap { extractTypeReference($0) }
                refs.append(TypeReference(name: name, genericArguments: genericArgs))
                pendingName = nil
            } else {
                // Flush pending name, then handle generic_type and other nodes.
                if let name = pendingName {
                    refs.append(TypeReference(name: name))
                    pendingName = nil
                }
                if let ref = extractTypeReference(child) {
                    refs.append(ref)
                }
            }
        }

        // Flush trailing simple name.
        if let name = pendingName {
            refs.append(TypeReference(name: name))
        }
        return refs
    }

    private func extractTypeList(_ node: Node) -> [TypeReference] {
        var refs: [TypeReference] = []
        for child in node.namedChildren() {
            if child.nodeType == "type_not_void_list" || child.nodeType == "_type_not_void_list" {
                refs.append(contentsOf: extractTypeListFromChildren(child))
            } else if let ref = extractTypeReference(child) {
                refs.append(ref)
            }
        }
        return refs
    }

    private func extractTypeListFromChildren(_ node: Node) -> [TypeReference] {
        return node.namedChildren().compactMap { extractTypeReference($0) }
    }

    // MARK: - Class Modifiers

    private func extractClassModifiers(_ node: Node) -> [Modifier] {
        var modifiers: [Modifier] = []
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            let modifierText = text(child)
            switch modifierText {
            case "abstract": modifiers.append(.abstract)
            case "sealed": modifiers.append(.sealed)
            case "final": modifiers.append(.final)
            default: break
            }
            if nodeType == "abstract" { modifiers.append(.abstract) }
            if nodeType == "sealed" { modifiers.append(.sealed) }
        }
        // Deduplicate.
        return Array(Set(modifiers))
    }

    // MARK: - Access Level

    /// In Dart, identifiers starting with `_` are private to the library.
    private func accessLevel(for name: String) -> AccessLevel {
        name.hasPrefix("_") ? .private : .public
    }
}
