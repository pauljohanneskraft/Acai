import AcaiCore
import AcaiTreeSitter

// MARK: - DartMemberExtractor

/// Shapes a `Member` value from a signature or field node plus its already-resolved pieces
/// (call sites, initial value, referenced type names) — mirrors `AcaiPython`'s
/// `PythonMemberExtractor`: this never resolves a call site or reads `DartExtractor`'s declaration
/// state itself, it only builds the value from what the caller already computed.
struct DartMemberExtractor {
    let context: SourceFileContext
    let typeReferences: DartTypeReferenceResolver
    let parameterExtractor: DartParameterExtractor
    /// From the pre-pass: a field initialised by constructing one of these gets that type.
    let declaredTypeNames: Set<String>

    // MARK: - Fields

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

    /// The pieces a field's initializer contributes.
    struct ValueReferences {
        var callSites: [CallSite] = []
        var initialValue: VariableAssignment.Value?
        var referencedTypeNames: [String] = []
    }

    /// A field declared by an `initialized_identifier`/`static_final_declaration` node, typed by
    /// `declaredType` or, failing that, by a direct construction initializer. `nil` when the node
    /// carries no identifier.
    func field(
        _ node: Node, declaredType: TypeReference?, attributes: FieldAttributes, references: ValueReferences
    ) -> Member? {
        let name = identifierName(of: node)
        guard !name.isEmpty else { return nil }
        return field(
            name: name, type: declaredType ?? constructedFieldType(from: node),
            attributes: attributes, location: node.location(in: context), references: references
        )
    }

    func field(
        name: String, type: TypeReference?, attributes: FieldAttributes, location: SourceLocation,
        references: ValueReferences = ValueReferences()
    ) -> Member {
        Member(
            name: name, kind: .property,
            accessLevel: DartName(name).accessLevel,
            modifiers: attributes.modifiers, type: type, location: location,
            callSites: references.callSites,
            initialValue: references.initialValue,
            referencedTypeNames: references.referencedTypeNames
        )
    }

    /// Infers a field's type from a direct construction initializer (`helper = Helper();`) with no
    /// explicit annotation. Flattened the same way `DartCallSiteSyntax` matches a bare call, so a
    /// known-type callee distinguishes a construction from an actual call (same check as
    /// `localBindings`).
    private func constructedFieldType(from node: Node) -> TypeReference? {
        let kids = node.namedChildren()
        guard kids.count >= 2,
              kids[kids.count - 1].nodeType == "selector",
              kids[kids.count - 1].firstChild(withType: "argument_part") != nil,
              kids[kids.count - 2].nodeType == "identifier",
              declaredTypeNames.contains(kids[kids.count - 2].text(in: context))
        else { return nil }
        return TypeReference(name: kids[kids.count - 2].text(in: context))
    }

    private func identifierName(of node: Node) -> String {
        for child in node.children() where child.nodeType == "identifier" {
            return child.text(in: context)
        }
        return ""
    }

    // MARK: - Enum Constants

    func enumConstant(_ node: Node) -> EnumCase? {
        let name = identifierName(of: node)
        guard !name.isEmpty else { return nil }
        return EnumCase(name: name, location: node.location(in: context))
    }
}
