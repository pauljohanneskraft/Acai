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
            return extractFunctionSignature(child)
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
        // In the Dart grammar a member's `function_body` is a *sibling* of its
        // signature node within the class body, so bodies are paired with the
        // member that the immediately preceding child produced.
        var previousChildAddedMember = false
        // (memberIndex, bodyNode) pairs; call sites are resolved after the loop so the
        // scope can be built from the type's *complete* property/member set.
        var pendingBodies: [(index: Int, body: Node)] = []
        // Annotations precede the member they decorate as siblings in the body.
        var pendingAnnotations: [String] = []
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "annotation" {
                pendingAnnotations.append(annotationText(child))
                continue
            }
            if nodeType == "function_body" {
                if previousChildAddedMember, !members.isEmpty {
                    members[members.count - 1].assignments = extractAssignments(from: child)
                    pendingBodies.append((members.count - 1, child))
                }
                previousChildAddedMember = false
                continue
            }
            let countBefore = members.count
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
            assignAnnotations(pendingAnnotations, toMembersFrom: countBefore, in: &members)
            pendingAnnotations = []
            previousChildAddedMember = members.count == countBefore + 1
        }
        attachCallSites(pendingBodies, to: &members)
    }

    /// Resolves and attaches call sites for the recorded method bodies, using a scope built
    /// from the type's fully-extracted members (so all stored properties are known) plus the
    /// current file's known type names.
    func attachCallSites(_ pendingBodies: [(index: Int, body: Node)], to members: inout [Member]) {
        guard !pendingBodies.isEmpty else { return }
        let scope = CallSiteScope(
            knownProperties: buildPropertyMap(from: members),
            knownTypeNames: declaredTypeNames
        )
        for pending in pendingBodies where pending.index < members.count {
            members[pending.index].callSites = extractCallSites(from: pending.body, scope: scope)
            members[pending.index].referencedTypeNames = referencedTypeNames(in: pending.body)
        }
    }

    /// Handles `declaration` nodes inside class bodies.
    ///
    /// A `declaration` node typically has the structure:
    ///   [modifiers] [type] [nullable_type?] (initialized_identifier_list | static_final_declaration_list)
    /// We extract the type and modifiers first, then propagate them to field extraction.
    private mutating func extractClassMemberDeclaration(
        _ node: Node,
        members: inout [Member],
        nestedTypes: inout [TypeDeclaration],
        parentName: String
    ) {
        let info = collectDeclarationInfo(node)

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "initialized_identifier_list" {
                members.append(contentsOf: extractFieldsFromIdentifierList(child, info: info))
            } else if nodeType == "static_final_declaration_list" {
                members.append(contentsOf: extractStaticFinalFields(child, info: info))
            } else if processClassMemberNode(
                child, nodeType: nodeType, members: &members,
                nestedTypes: &nestedTypes, parentName: parentName
            ) {
                continue
            } else if let fields = extractFieldFromDeclarationChild(child) {
                members.append(contentsOf: fields)
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
        // Same signature/body sibling pairing as `extractClassBody`.
        var previousChildAddedMember = false
        var pendingBodies: [(index: Int, body: Node)] = []
        var pendingAnnotations: [String] = []
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "annotation" {
                pendingAnnotations.append(annotationText(child))
                continue
            }
            let countBefore = members.count
            switch nodeType {
            case "enum_constant":
                if let enumCase = extractEnumConstant(child) { enumCases.append(enumCase) }
            case "function_body":
                if previousChildAddedMember, !members.isEmpty {
                    members[members.count - 1].assignments = extractAssignments(from: child)
                    pendingBodies.append((members.count - 1, child))
                }
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
            assignAnnotations(pendingAnnotations, toMembersFrom: countBefore, in: &members)
            pendingAnnotations = []
            previousChildAddedMember = members.count == countBefore + 1
        }
        attachCallSites(pendingBodies, to: &members)
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

    /// Wraps a property member with the method_signature's static modifier if needed.
    private func wrapPropertyMember(_ member: Member, isStatic: Bool, at node: Node) -> Member {
        var mods = member.modifiers
        if isStatic, !mods.contains(.static) { mods.append(.static) }
        return Member(
            name: member.name, kind: member.kind,
            accessLevel: member.accessLevel, modifiers: mods,
            type: member.type, isComputed: member.isComputed,
            location: loc(node)
        )
    }

    /// Attempts to resolve a child of a `method_signature` into a member
    /// for signatures that are returned directly (constructor, getter, setter, operator).
    private func resolveMethodSignatureChild(
        _ child: Node, nodeType: String, isStatic: Bool, at node: Node
    ) -> Member? {
        switch nodeType {
        case "constructor_signature":
            return extractConstructorSignature(child, parentName: "").map { member in
                Member(
                    name: member.name, kind: member.kind,
                    modifiers: isStatic ? member.modifiers + [.static] : member.modifiers,
                    type: member.type, parameters: member.parameters, location: loc(node)
                )
            }
        case "getter_signature":
            return extractGetterSignature(child).map { wrapPropertyMember($0, isStatic: isStatic, at: node) }
        case "setter_signature":
            return extractSetterSignature(child).map { wrapPropertyMember($0, isStatic: isStatic, at: node) }
        case "operator_signature":
            return extractOperatorSignature(child)
        default:
            return nil
        }
    }

    private func extractMethodSignature(_ node: Node) -> Member? {
        let isStatic = node.hasAnonymousChild("static", in: context)
        var returnType: TypeReference?
        var name = ""
        var parameters: [Parameter] = []
        var genericParams: [GenericParameter] = []

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if let member = resolveMethodSignatureChild(
                child, nodeType: nodeType, isStatic: isStatic, at: node
            ) {
                return member
            }
            if nodeType == "function_signature" {
                let inner = extractFunctionSignatureInner(child)
                returnType = inner.returnType
                name = inner.name
                parameters = inner.parameters
                genericParams = inner.genericParameters
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

    func extractFunctionSignature(_ node: Node) -> Member? {
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
        var returnType: TypeReference?
        var operatorName = "operator"
        var parameters: [Parameter] = []

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "type_identifier", "void_type":
                if returnType == nil { returnType = extractTypeReference(child) }
            case "binary_operator", "unary_prefix_operator", "unary_postfix_operator",
                 "tilde_operator", "minus_operator", "negation_operator":
                operatorName = text(child).trimmingCharacters(in: .whitespacesAndNewlines)
            case "formal_parameter_list":
                parameters = extractFormalParameterList(child)
            default:
                break
            }
        }

        return Member(
            name: operatorName, kind: .method,
            type: returnType, parameters: parameters,
            location: loc(node)
        )
    }
}
