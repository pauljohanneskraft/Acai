import UMLCore
import UMLTreeSitter

// MARK: - Body Extraction & Member Signatures

extension DartExtractor {

    private func extractMemberFromSignature(
        _ child: Node, nodeType: String, parentName: String
    ) -> Member? {
        switch nodeType {
        case "method_signature":
            return extractMethodSignature(child)
        case "function_signature":
            return extractFunctionSignature(child, isTopLevel: false)
        case "constructor_signature", "constant_constructor_signature":
            return extractConstructorSignature(child, parentName: parentName)
        case "factory_constructor_signature", "redirecting_factory_constructor_signature":
            return extractFactoryConstructorSignature(child)
        case "getter_signature":
            return extractGetterSignature(child)
        case "setter_signature":
            return extractSetterSignature(child)
        case "operator_signature":
            return extractOperatorSignature(child)
        default:
            return nil
        }
    }

    private mutating func extractNestedType(
        _ child: Node, nodeType: String
    ) -> TypeDeclaration? {
        switch nodeType {
        case "class_definition":
            return extractClassDefinition(child)
        case "enum_declaration":
            return extractEnumDeclaration(child)
        case "mixin_declaration":
            return extractMixinDeclaration(child)
        default:
            return nil
        }
    }

    @discardableResult
    private mutating func processClassMemberNode(
        _ child: Node,
        nodeType: String,
        members: inout [Member],
        nestedTypes: inout [TypeDeclaration],
        parentName: String
    ) -> Bool {
        if let member = extractMemberFromSignature(
            child, nodeType: nodeType, parentName: parentName
        ) {
            members.append(member)
            return true
        }
        if nodeType == "static_final_declaration_list"
            || nodeType == "initialized_identifier_list" {
            members.append(contentsOf: extractFieldDeclarations(child))
            return true
        }
        if let typeDecl = extractNestedType(child, nodeType: nodeType) {
            nestedTypes.append(typeDecl)
            return true
        }
        return false
    }

    mutating func extractClassBody(
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

    mutating func extractEnumBody(
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

    func extractFunctionSignature(_ node: Node, isTopLevel: Bool) -> Member? {
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

    private func applyFunctionSignatureChild(
        _ child: Node, nodeType: String, to info: inout FunctionSignatureInfo
    ) {
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
            if info.returnType == nil, let ref = extractTypeReference(child) {
                info.returnType = ref
            }
        }
    }

    private func extractFunctionSignatureInner(_ node: Node) -> FunctionSignatureInfo {
        var info = FunctionSignatureInfo()
        if let nameNode = node.child(byFieldName: "name") {
            info.name = text(nameNode)
        }
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            applyFunctionSignatureChild(child, nodeType: nodeType, to: &info)
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

    private struct FieldAttributes {
        var isStatic: Bool = false
        var isLate: Bool = false
        var isConst: Bool = false
        var isFinal: Bool = false

        var modifiers: [Modifier] {
            var result: [Modifier] = []
            if isStatic { result.append(.static) }
            if isLate { result.append(.late) }
            if isConst { result.append(.const) }
            if isFinal { result.append(.final) }
            return result
        }
    }

    private func makeFieldMember(
        name: String, type: TypeReference?,
        attributes: FieldAttributes, location: SourceLocation
    ) -> Member {
        Member(
            name: name, kind: .property,
            accessLevel: accessLevel(for: name),
            modifiers: attributes.modifiers, type: type, location: location
        )
    }

    private func processFieldChild(
        _ child: Node, nodeType: String,
        fieldType: inout TypeReference?, attributes: FieldAttributes
    ) -> [Member] {
        switch nodeType {
        case "type_identifier", "generic_type", "function_type":
            if fieldType == nil { fieldType = extractTypeReference(child) }
            return []
        case "initialized_identifier":
            let varName = extractIdentifierName(child)
            guard !varName.isEmpty else { return [] }
            return [makeFieldMember(
                name: varName, type: fieldType,
                attributes: attributes, location: loc(child)
            )]
        case "static_final_declaration":
            let varName = extractIdentifierName(child)
            guard !varName.isEmpty else { return [] }
            var attrs = attributes
            attrs.isStatic = true
            attrs.isLate = false
            attrs.isFinal = true
            return [makeFieldMember(
                name: varName, type: fieldType,
                attributes: attrs, location: loc(child)
            )]
        case "identifier":
            return processFieldIdentifier(
                child, fieldType: &fieldType, attributes: attributes
            )
        default:
            return []
        }
    }

    private func processFieldIdentifier(
        _ child: Node, fieldType: inout TypeReference?,
        attributes: FieldAttributes
    ) -> [Member] {
        let varName = text(child)
        guard !varName.isEmpty, !varName.hasPrefix("var"),
              !varName.hasPrefix("final") else { return [] }
        if fieldType == nil {
            fieldType = TypeReference(name: varName)
            return []
        }
        var attrs = attributes
        attrs.isConst = false
        return [makeFieldMember(
            name: varName, type: fieldType,
            attributes: attrs, location: loc(child)
        )]
    }

    private func extractFieldDeclarations(_ node: Node) -> [Member] {
        let attributes = FieldAttributes(
            isStatic: node.hasAnonymousChild("static", in: context),
            isLate: node.hasAnonymousChild("late", in: context),
            isConst: node.nodeType == "static_final_declaration_list"
                || node.hasAnonymousChild("const", in: context)
                || node.hasAnonymousChild("final", in: context)
        )
        var members: [Member] = []
        var fieldType: TypeReference?
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            members.append(contentsOf: processFieldChild(
                child, nodeType: nodeType, fieldType: &fieldType,
                attributes: attributes
            ))
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
