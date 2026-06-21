import Foundation
import UMLCore
import UMLTreeSitter

// MARK: - Member, global, and function extraction

extension CFamilyExtractor {

    private static let memberDeclaratorTypes: Set<String> = [
        "identifier", "field_identifier", "pointer_declarator", "array_declarator",
        "function_declarator", "init_declarator", "reference_declarator",
        "qualified_identifier", "operator_name", "destructor_name"
    ]

    // MARK: - Record body

    mutating func extractRecordBody(
        _ body: Node, ownerName: String, defaultAccess: AccessLevel,
        members: inout [Member], nestedTypes: inout [TypeDeclaration]
    ) {
        var access = defaultAccess
        // (memberIndex, bodyNode) pairs; call sites/assignments are resolved after the loop so the
        // scope can be built from the type's *complete* property/member set.
        var pendingBodies: [(index: Int, body: Node)] = []
        for child in body.namedChildren() {
            switch child.nodeType {
            case "access_specifier":
                access = accessLevel(from: child) ?? access
            case "field_declaration":
                appendField(child, ownerName: ownerName, access: access,
                            members: &members, nestedTypes: &nestedTypes)
            case "function_definition":
                if let method = functionMember(from: child, ownerName: ownerName, access: access) {
                    members.append(method)
                    if let methodBody = child.child(byFieldName: "body") {
                        pendingBodies.append((members.count - 1, methodBody))
                    }
                }
            case "struct_specifier", "union_specifier", "class_specifier", "enum_specifier":
                appendNestedType(child, into: &nestedTypes)
            case "template_declaration":
                appendTemplateMember(child, ownerName: ownerName, access: access,
                                     members: &members, nestedTypes: &nestedTypes)
            default:
                break
            }
        }
        attachBodies(pendingBodies, to: &members)
    }

    /// Resolves and attaches call sites + assignments for the recorded method bodies, using a scope
    /// built from the type's fully-extracted members (so all stored properties are known) plus the
    /// current file's known type names.
    private func attachBodies(_ pendingBodies: [(index: Int, body: Node)], to members: inout [Member]) {
        guard !pendingBodies.isEmpty else { return }
        let scope = CallSiteScope(
            knownProperties: buildPropertyMap(from: members),
            knownTypeNames: collectKnownTypeNames()
        )
        for pending in pendingBodies where pending.index < members.count {
            members[pending.index].callSites = extractCallSites(from: pending.body, scope: scope)
            members[pending.index].assignments = extractAssignments(from: pending.body)
        }
    }

    private mutating func appendField(
        _ node: Node, ownerName: String, access: AccessLevel,
        members: inout [Member], nestedTypes: inout [TypeDeclaration]
    ) {
        if let typeNode = node.child(byFieldName: "type") {
            appendNestedType(typeNode, into: &nestedTypes)
        }
        for declarator in declarators(of: node) {
            let info = parseDeclarator(declarator)
            guard !info.name.isEmpty else { continue }
            if info.isFunction {
                members.append(methodMember(node: node, info: info, ownerName: ownerName, access: access))
            } else {
                members.append(propertyMember(node: node, info: info, access: access))
            }
        }
    }

    @discardableResult
    private mutating func appendNestedType(_ node: Node, into nestedTypes: inout [TypeDeclaration]) -> Bool {
        guard node.child(byFieldName: "body") != nil else { return false }
        switch node.nodeType {
        case "struct_specifier", "union_specifier", "class_specifier":
            if let decl = extractRecord(node) { nestedTypes.append(decl); return true }
        case "enum_specifier":
            if let decl = extractEnum(node) { nestedTypes.append(decl); return true }
        default:
            break
        }
        return false
    }

    private mutating func appendTemplateMember(
        _ node: Node, ownerName: String, access: AccessLevel,
        members: inout [Member], nestedTypes: inout [TypeDeclaration]
    ) {
        for child in node.namedChildren() {
            switch child.nodeType {
            case "function_definition":
                if let method = functionMember(from: child, ownerName: ownerName, access: access) {
                    members.append(method)
                }
            case "field_declaration":
                appendField(child, ownerName: ownerName, access: access,
                            members: &members, nestedTypes: &nestedTypes)
            case "class_specifier", "struct_specifier", "union_specifier":
                appendNestedType(child, into: &nestedTypes)
            default:
                break
            }
        }
    }

    // MARK: - Top-level globals & prototypes

    mutating func extractTopLevelDeclarators(_ node: Node) {
        for declarator in declarators(of: node) {
            let info = parseDeclarator(declarator)
            guard !info.name.isEmpty else { continue }
            if info.isFunction {
                freestandingFunctions.append(
                    methodMember(node: node, info: info, ownerName: nil, access: .public))
            } else {
                let typeRef = typeReference(from: node.child(byFieldName: "type"), declarator: info)
                globalVariables.append(Member(
                    name: Self.lastComponent(of: info.name), kind: .property,
                    accessLevel: .public, modifiers: modifiers(from: node),
                    type: typeRef, location: loc(node)))
            }
        }
    }

    /// Builds a member for a free `function_definition` (or `nil` if the declarator is not a
    /// function), resolving the body's call sites + assignments against the file's known functions.
    mutating func extractFunctionDefinition(_ node: Node, defaultAccess: AccessLevel) -> Member? {
        guard var member = functionMember(from: node, ownerName: nil, access: defaultAccess) else {
            return nil
        }
        if let body = node.child(byFieldName: "body") {
            let scope = CallSiteScope(knownProperties: [:], knownTypeNames: collectKnownTypeNames())
            member.callSites = extractCallSites(from: body, scope: scope)
            member.assignments = extractAssignments(from: body)
        }
        return member
    }

    private mutating func functionMember(from node: Node, ownerName: String?, access: AccessLevel) -> Member? {
        let info = parseDeclarator(node.child(byFieldName: "declarator"))
        guard info.isFunction, !info.name.isEmpty else { return nil }
        return methodMember(node: node, info: info, ownerName: ownerName, access: access)
    }

    private func methodMember(
        node: Node, info: CFamilyDeclarator, ownerName: String?, access: AccessLevel
    ) -> Member {
        let simpleName = Self.lastComponent(of: info.name)
        let returnType = typeReference(from: node.child(byFieldName: "type"), declarator: CFamilyDeclarator())
        let kind = memberKind(name: simpleName, ownerName: ownerName, hasReturnType: returnType != nil)
        return Member(
            name: simpleName, kind: kind, accessLevel: access,
            modifiers: modifiers(from: node),
            type: kind == .method ? returnType : nil,
            parameters: info.parameters, location: loc(node))
    }

    private func propertyMember(node: Node, info: CFamilyDeclarator, access: AccessLevel) -> Member {
        // A C++ default member initializer (`State state = State::idle;`) seeds the field's value,
        // which the state-diagram value-flow analysis reads as the machine's initial state.
        let initialValue = node.child(byFieldName: "default_value").map { classifyValue($0) }
        return Member(
            name: Self.lastComponent(of: info.name), kind: .property, accessLevel: access,
            modifiers: modifiers(from: node),
            type: typeReference(from: node.child(byFieldName: "type"), declarator: info),
            location: loc(node), initialValue: initialValue)
    }

    // MARK: - Helpers

    private func declarators(of node: Node) -> [Node] {
        // Exclude the `type` field: a type can itself be a `qualified_identifier`/`type_identifier`,
        // which also appears in `memberDeclaratorTypes` (needed for out-of-line `Foo::bar` names).
        let typeRange = node.child(byFieldName: "type")?.range
        return node.namedChildren().filter { child in
            Self.memberDeclaratorTypes.contains(child.nodeType ?? "") && child.range != typeRange
        }
    }

    private func memberKind(name: String, ownerName: String?, hasReturnType: Bool) -> MemberKind {
        if name.hasPrefix("~") { return .deinitializer }
        if let ownerName, name == ownerName, !hasReturnType { return .initializer }
        return .method
    }

    private func accessLevel(from node: Node) -> AccessLevel? {
        switch text(node).trimmingCharacters(in: .whitespaces) {
        case "public":
            return .public
        case "protected":
            return .protected
        case "private":
            return .private
        default:
            return nil
        }
    }

    private func modifiers(from node: Node) -> [Modifier] {
        var modifiers: [Modifier] = []
        var isVirtual = false
        for child in node.children() {
            if let modifier = Self.modifier(forChildType: child.nodeType, text: text(child)) {
                modifiers.append(modifier)
            } else if Self.isVirtualMarker(nodeType: child.nodeType, text: text(child), isNamed: child.isNamed) {
                isVirtual = true
            }
        }
        // No plain `virtual` modifier exists in the closed `Modifier` enum; a pure virtual (`= 0`)
        // maps to `.abstract`, an ordinary virtual is left unmarked.
        if isVirtual, let defaultValue = node.child(byFieldName: "default_value"), text(defaultValue) == "0" {
            modifiers.append(.abstract)
        }
        return modifiers
    }

    private static func modifier(forChildType nodeType: String?, text: String) -> Modifier? {
        switch nodeType {
        case "storage_class_specifier":
            return storageClassModifier(text)
        case "type_qualifier":
            return typeQualifierModifier(text)
        case "virtual_specifier":
            return virtualSpecifierModifier(text)
        default:
            return nil
        }
    }

    private static func storageClassModifier(_ text: String) -> Modifier? {
        switch text {
        case "static":
            return .static
        case "extern":
            return .external
        case "inline":
            return .inline
        default:
            return nil
        }
    }

    private static func typeQualifierModifier(_ text: String) -> Modifier? {
        switch text {
        case "const":
            return .const
        case "volatile":
            return .volatile
        default:
            return nil
        }
    }

    private static func virtualSpecifierModifier(_ text: String) -> Modifier? {
        switch text {
        case "override":
            return .override
        case "final":
            return .final
        default:
            return nil
        }
    }

    private static func isVirtualMarker(nodeType: String?, text: String, isNamed: Bool) -> Bool {
        nodeType == "virtual_function_specifier" || (!isNamed && text == "virtual")
    }
}
