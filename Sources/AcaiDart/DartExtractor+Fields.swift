import AcaiCore
import AcaiTreeSitter

// MARK: - Field Declarations

extension DartExtractor {

    private typealias FieldAttributes = DartMemberExtractor.FieldAttributes

    /// Extracts field members from an `initialized_identifier_list` node.
    func extractFieldsFromIdentifierList(
        _ node: Node, info: DartTypeReferenceResolver.DeclarationInfo
    ) -> [Member] {
        let attrs = FieldAttributes(
            isStatic: info.isStatic, isLate: info.isLate,
            isConst: info.isConst, isFinal: info.isFinal
        )
        return node.allChildren(withType: "initialized_identifier").compactMap { child in
            memberExtractor.field(child, declaredType: info.type, attributes: attrs, references: references(of: child))
        }
    }

    /// Extracts field members from a `static_final_declaration_list` node.
    func extractStaticFinalFields(
        _ node: Node, info: DartTypeReferenceResolver.DeclarationInfo
    ) -> [Member] {
        let attrs = FieldAttributes(
            isStatic: info.isStatic, isLate: info.isLate,
            isConst: true, isFinal: true
        )
        return node.allChildren(withType: "static_final_declaration").compactMap { child in
            memberExtractor.field(child, declaredType: info.type, attributes: attrs, references: references(of: child))
        }
    }

    /// What a field's initializer contributes. A field initializer can't reference `this`, so
    /// file-level type names are the only resolvable receivers.
    private func references(of node: Node) -> DartMemberExtractor.ValueReferences {
        .init(
            callSites: callSites.callSites(
                in: node, scope: CallSiteScope(knownTypeNames: declarations.declaredTypeNames)),
            initialValue: assignmentSyntax.fieldInitializerValue(of: node),
            referencedTypeNames: node.referencedTypeNames(in: context)
        )
    }

    // MARK: - Bare identifier lists

    private func processFieldChild(
        _ child: Node, nodeType: String,
        fieldType: inout TypeReference?, attributes: FieldAttributes
    ) -> [Member] {
        switch nodeType {
        case "type_identifier", "generic_type", "function_type":
            if fieldType == nil { fieldType = typeReferences.typeReference(child) }
            return []
        case "initialized_identifier":
            return memberExtractor.field(
                child, declaredType: fieldType, attributes: attributes,
                references: .init(initialValue: assignmentSyntax.fieldInitializerValue(of: child))
            ).map { [$0] } ?? []
        case "static_final_declaration":
            var attrs = attributes
            attrs.isStatic = true
            attrs.isLate = false
            attrs.isFinal = true
            return memberExtractor.field(
                child, declaredType: fieldType, attributes: attrs,
                references: .init(initialValue: assignmentSyntax.fieldInitializerValue(of: child))
            ).map { [$0] } ?? []
        case "identifier":
            return processFieldIdentifier(child, fieldType: &fieldType, attributes: attributes)
        default:
            return []
        }
    }

    private func processFieldIdentifier(
        _ child: Node, fieldType: inout TypeReference?,
        attributes: FieldAttributes
    ) -> [Member] {
        let varName = child.text(in: context)
        guard !varName.isEmpty, !varName.hasPrefix("var"),
              !varName.hasPrefix("final") else { return [] }
        if fieldType == nil {
            fieldType = TypeReference(name: varName)
            return []
        }
        var attrs = attributes
        attrs.isConst = false
        return [memberExtractor.field(
            name: varName, type: fieldType, attributes: attrs, location: child.location(in: context)
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

    func extractFieldFromDeclarationChild(_ child: Node) -> [Member]? {
        guard let nodeType = child.nodeType else { return nil }
        switch nodeType {
        case "static_final_declaration_list", "initialized_identifier_list":
            return extractFieldDeclarations(child)
        default:
            return nil
        }
    }
}
