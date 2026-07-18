import AcaiCore
import AcaiTreeSitter

// MARK: - Field Declarations & Declaration Info

extension DartExtractor {

    // MARK: - Declaration Info

    /// Collected declaration-level type and modifier information.
    struct DeclarationInfo {
        var type: TypeReference?
        var isNullable = false
        var isStatic = false
        var isLate = false
        var isFinal = false
        var isConst = false
    }

    /// Applies a single child node to accumulate declaration info.
    private func applyDeclarationChild(
        _ child: Node, nodeType: String, to info: inout DeclarationInfo
    ) {
        switch nodeType {
        case "type_identifier", "generic_type", "function_type", "void_type":
            if info.type == nil { info.type = extractTypeReference(child) }
        case "type_arguments":
            if let base = info.type {
                let args = child.namedChildren().compactMap { extractTypeReference($0) }
                info.type = TypeReference(
                    name: base.name, genericArguments: args,
                    isArray: base.name == "List"
                )
            }
        case "nullable_type":
            info.isNullable = true
        case "final_builtin":
            info.isFinal = true
        case "const_builtin":
            info.isConst = true
        default:
            break
        }
    }

    /// First pass over a `declaration` node to collect type and modifier info.
    func collectDeclarationInfo(_ node: Node) -> DeclarationInfo {
        var info = DeclarationInfo(
            isStatic: node.hasAnonymousChild("static", in: context),
            isLate: node.hasAnonymousChild("late", in: context)
        )
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            applyDeclarationChild(child, nodeType: nodeType, to: &info)
        }
        if info.isNullable, let base = info.type {
            info.type = TypeReference(
                name: base.name, genericArguments: base.genericArguments,
                isOptional: true, isArray: base.isArray
            )
        }
        return info
    }

    /// Extracts field members from an `initialized_identifier_list` node
    /// using the given declaration-level info.
    func extractFieldsFromIdentifierList(
        _ node: Node, info: DeclarationInfo
    ) -> [Member] {
        let attrs = FieldAttributes(
            isStatic: info.isStatic, isLate: info.isLate,
            isConst: info.isConst, isFinal: info.isFinal
        )
        return node.allChildren(withType: "initialized_identifier").compactMap { child in
            let name = extractIdentifierName(child)
            guard !name.isEmpty else { return nil }
            return makeFieldMember(
                name: name, type: info.type ?? constructedFieldType(from: child),
                attributes: attrs, location: loc(child),
                initialValue: fieldInitializerValue(of: child), node: child
            )
        }
    }

    /// Extracts field members from a `static_final_declaration_list` node
    /// using the given declaration-level info.
    func extractStaticFinalFields(
        _ node: Node, info: DeclarationInfo
    ) -> [Member] {
        let attrs = FieldAttributes(
            isStatic: info.isStatic, isLate: info.isLate,
            isConst: true, isFinal: true
        )
        return node.allChildren(withType: "static_final_declaration").compactMap { child in
            let name = extractIdentifierName(child)
            guard !name.isEmpty else { return nil }
            return makeFieldMember(
                name: name, type: info.type ?? constructedFieldType(from: child),
                attributes: attrs, location: loc(child),
                initialValue: fieldInitializerValue(of: child), node: child
            )
        }
    }

    /// Infers a field's type from a direct construction initializer (`helper = Helper();`) when
    /// there's no explicit annotation — the idiomatic Dart form for a composed collaborator.
    /// The grammar flattens this the same way `resolveCallSite` matches a bare call inside an
    /// `initialized_identifier` (`[…, callee-id, selector(argument_part)]`), so a known-type
    /// callee is what distinguishes a construction from an actual call — the same check
    /// `localBindings` already applies to locals.
    private func constructedFieldType(from node: Node) -> TypeReference? {
        let kids = node.namedChildren()
        guard kids.count >= 2,
              kids[kids.count - 1].nodeType == "selector",
              kids[kids.count - 1].firstChild(withType: "argument_part") != nil,
              kids[kids.count - 2].nodeType == "identifier",
              declaredTypeNames.contains(text(kids[kids.count - 2]))
        else { return nil }
        return TypeReference(name: text(kids[kids.count - 2]))
    }

    // MARK: - Field Attributes & Helpers

    struct FieldAttributes {
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

    func makeFieldMember(
        name: String, type: TypeReference?,
        attributes: FieldAttributes, location: SourceLocation,
        initialValue: VariableAssignment.Value? = nil,
        node: Node? = nil
    ) -> Member {
        Member(
            name: name, kind: .property,
            accessLevel: accessLevel(for: name),
            modifiers: attributes.modifiers, type: type, location: location,
            // A field initializer can't reference `this`, so file-level type names are the only
            // resolvable receivers — enough to record its calls (RC2) without the type's field map.
            callSites: extractCallSites(from: node, scope: CallSiteScope(knownTypeNames: declaredTypeNames)),
            initialValue: initialValue,
            referencedTypeNames: referencedTypeNames(in: node)
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
                name: varName, type: fieldType ?? constructedFieldType(from: child),
                attributes: attributes, location: loc(child),
                initialValue: fieldInitializerValue(of: child)
            )]
        case "static_final_declaration":
            let varName = extractIdentifierName(child)
            guard !varName.isEmpty else { return [] }
            var attrs = attributes
            attrs.isStatic = true
            attrs.isLate = false
            attrs.isFinal = true
            return [makeFieldMember(
                name: varName, type: fieldType ?? constructedFieldType(from: child),
                attributes: attrs, location: loc(child),
                initialValue: fieldInitializerValue(of: child)
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

    func extractFieldDeclarations(_ node: Node) -> [Member] {
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
    func extractFieldFromDeclarationChild(_ child: Node) -> [Member]? {
        guard let nodeType = child.nodeType else { return nil }
        switch nodeType {
        case "static_final_declaration_list", "initialized_identifier_list":
            return extractFieldDeclarations(child)
        default:
            return nil
        }
    }

    func extractIdentifierName(_ node: Node) -> String {
        for child in node.children() where child.nodeType == "identifier" {
            return text(child)
        }
        return ""
    }
}
