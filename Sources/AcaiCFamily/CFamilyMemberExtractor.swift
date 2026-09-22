import Foundation
import AcaiCore
import AcaiTreeSitter

// MARK: - CFamilyMemberExtractor

/// Shapes a `Member` from a C/C++ declaration node and one of its parsed declarators: methods,
/// fields, free functions and globals, with their storage-class/qualifier modifiers. It never reads
/// `CFamilyExtractor`'s declaration state; the file-level type names it needs arrive from the
/// pre-pass.
struct CFamilyMemberExtractor {
    let context: SourceFileContext
    let typeReferences: CFamilyTypeReferenceResolver
    let assignmentSyntax: CFamilyAssignmentSyntax
    let callSites: CallSiteResolver
    /// From the pre-pass: the only receivers a default member initializer can resolve.
    let declaredTypeNames: Set<String>

    // MARK: - Functions & Methods

    func functionMember(from node: Node, ownerName: String?, access: AccessLevel) -> Member? {
        let info = typeReferences.parseDeclarator(node.child(byFieldName: "declarator"))
        guard info.isFunction, !info.name.isEmpty else { return nil }
        return methodMember(node: node, info: info, ownerName: ownerName, access: access)
    }

    func methodMember(
        node: Node, info: CFamilyDeclarator, ownerName: String?, access: AccessLevel
    ) -> Member {
        let simpleName = typeReferences.lastComponent(of: info.name)
        let returnType = typeReferences.typeReference(
            from: node.child(byFieldName: "type"), declarator: CFamilyDeclarator())
        let kind = memberKind(name: simpleName, ownerName: ownerName, hasReturnType: returnType != nil)
        let functionModifiers = modifiers(from: node)
        return Member(
            name: simpleName, kind: kind,
            accessLevel: freeFunctionAccessLevel(
                default: access, ownerName: ownerName, modifiers: functionModifiers),
            modifiers: functionModifiers,
            type: kind == .method ? returnType : nil,
            parameters: info.parameters, location: node.location(in: context))
    }

    /// A `static` free function (or prototype) has internal linkage: it is only reachable from its
    /// own translation unit, C's closest equivalent to `private`. `.filePrivate` (rather than
    /// `.private`) matches that "visible within this file" scope; a `static` *member* function is
    /// an unrelated concept (a class-scoped function with no `self`), so `ownerName != nil` is left
    /// at its passed-in access level.
    private func freeFunctionAccessLevel(
        default access: AccessLevel, ownerName: String?, modifiers: [Modifier]
    ) -> AccessLevel {
        ownerName == nil && modifiers.contains(.static) ? .filePrivate : access
    }

    private func memberKind(name: String, ownerName: String?, hasReturnType: Bool) -> MemberKind {
        if name.hasPrefix("~") { return .deinitializer }
        if let ownerName, name == ownerName, !hasReturnType { return .initializer }
        return .method
    }

    // MARK: - Fields & Globals

    func propertyMember(node: Node, info: CFamilyDeclarator, access: AccessLevel) -> Member {
        // A C++ default member initializer (`State state = State::idle;`) seeds the field's value,
        // which the state-diagram value-flow analysis reads as the machine's initial state.
        let initialValue = node.child(byFieldName: "default_value").map { assignmentSyntax.classifyValue($0) }
        return Member(
            name: typeReferences.lastComponent(of: info.name), kind: .property, accessLevel: access,
            modifiers: modifiers(from: node),
            type: typeReferences.typeReference(from: node.child(byFieldName: "type"), declarator: info),
            location: node.location(in: context),
            // A default member initializer's calls (`int n = compute();`) are recorded so their targets
            // aren't false-flagged dead. File-level type names cover static/`Type::method()` calls.
            callSites: callSites.callSites(
                in: node.child(byFieldName: "default_value"),
                scope: CallSiteScope(knownTypeNames: declaredTypeNames)),
            initialValue: initialValue,
            referencedTypeNames: node.child(byFieldName: "default_value")?.referencedTypeNames(in: context) ?? [])
    }

    func globalVariable(node: Node, info: CFamilyDeclarator) -> Member {
        Member(
            name: typeReferences.lastComponent(of: info.name), kind: .property,
            accessLevel: .public, modifiers: modifiers(from: node),
            type: typeReferences.typeReference(from: node.child(byFieldName: "type"), declarator: info),
            location: node.location(in: context))
    }

    // MARK: - Access & Modifiers

    func accessLevel(from node: Node) -> AccessLevel? {
        switch node.text(in: context).trimmingCharacters(in: .whitespaces) {
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
            if let modifier = modifier(forChildType: child.nodeType, text: child.text(in: context)) {
                modifiers.append(modifier)
            } else if isVirtualMarker(nodeType: child.nodeType, text: child.text(in: context), isNamed: child.isNamed) {
                isVirtual = true
            }
        }
        // No plain `virtual` modifier exists in the closed `Modifier` enum; a pure virtual (`= 0`)
        // maps to `.abstract`, an ordinary virtual is left unmarked.
        if isVirtual, let defaultValue = node.child(byFieldName: "default_value"),
           defaultValue.text(in: context) == "0" {
            modifiers.append(.abstract)
        }
        return modifiers
    }

    private func modifier(forChildType nodeType: String?, text: String) -> Modifier? {
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

    private func storageClassModifier(_ text: String) -> Modifier? {
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

    private func typeQualifierModifier(_ text: String) -> Modifier? {
        switch text {
        case "const":
            return .const
        case "volatile":
            return .volatile
        default:
            return nil
        }
    }

    private func virtualSpecifierModifier(_ text: String) -> Modifier? {
        switch text {
        case "override":
            return .override
        case "final":
            return .final
        default:
            return nil
        }
    }

    private func isVirtualMarker(nodeType: String?, text: String, isNamed: Bool) -> Bool {
        nodeType == "virtual_function_specifier" || (!isNamed && text == "virtual")
    }
}
