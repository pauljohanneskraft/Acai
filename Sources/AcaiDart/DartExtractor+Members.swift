import AcaiCore
import AcaiTreeSitter

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
        // A member's `function_body` is a *sibling* of its signature node, paired with whichever
        // member the immediately preceding child produced.
        var previousChildAddedMember = false
        // Call sites are resolved after the loop so the scope reflects the type's full member set.
        var pendingBodies: [(index: Int, body: Node)] = []
        var pendingAnnotations: [String] = []
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "annotation" {
                pendingAnnotations.append(annotationText(child))
                continue
            }
            if nodeType == "function_body" {
                attachFunctionBody(
                    child, previousChildAddedMember: previousChildAddedMember,
                    members: &members, pendingBodies: &pendingBodies
                )
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
            // A constructor's initializer list (`: x = compute()`) lives inside `method_signature`;
            // walk it so its calls aren't lost. Runs before `this`, so file-level type names resolve
            // its static/top-level receivers.
            if previousChildAddedMember, let initializers = child.firstChild(withType: "initializers") {
                appendInitializerListCallSites(initializers, to: &members)
            }
        }
        attachCallSites(pendingBodies, to: &members)
        markBodylessMethodsAbstract(&members, bodiedIndices: Set(pendingBodies.map(\.index)))
    }

    /// Handles `declaration` nodes inside class bodies: `[modifiers] [type] [nullable_type?]
    /// (initialized_identifier_list | static_final_declaration_list)`. Extracts type/modifiers
    /// first, then propagates them to field extraction.
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

    /// Attaches a `function_body` sibling to the member it belongs to: assignments extracted from
    /// its statements, and `.async` when the body carries an `async`/`async*`/`sync*` marker.
    private func attachFunctionBody(
        _ node: Node,
        previousChildAddedMember: Bool,
        members: inout [Member],
        pendingBodies: inout [(index: Int, body: Node)]
    ) {
        guard previousChildAddedMember, !members.isEmpty else { return }
        members[members.count - 1].assignments = extractAssignments(from: node)
        if isAsyncFunctionBody(node) {
            members[members.count - 1].modifiers.append(.async)
        }
        pendingBodies.append((members.count - 1, node))
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
                attachFunctionBody(
                    child, previousChildAddedMember: previousChildAddedMember,
                    members: &members, pendingBodies: &pendingBodies
                )
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
            // A constructor's initializer list (`: x = compute()`) lives inside `method_signature`;
            // walk it so its calls aren't lost. Runs before `this`, so file-level type names resolve
            // its static/top-level receivers.
            if previousChildAddedMember, let initializers = child.firstChild(withType: "initializers") {
                appendInitializerListCallSites(initializers, to: &members)
            }
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
}
