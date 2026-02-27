import UMLCore
import UMLTreeSitter

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
