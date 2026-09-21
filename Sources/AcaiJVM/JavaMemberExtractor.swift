import AcaiCore
import AcaiTreeSitter

// MARK: - JavaMemberExtractor

/// Shapes a `Member` value from an already-parsed method/field/element node plus its
/// already-resolved pieces (modifiers, generics, parameters, return type, call sites, assignments,
/// field reads) — mirrors `AcaiPython`'s `PythonMemberExtractor`: this never resolves a call site or
/// reads `JavaExtractor`'s declaration state itself, it only builds the value from what the caller
/// already computed.
struct JavaMemberExtractor {
    let context: SourceFileContext

    /// Fully resolved pieces a method/constructor body contributes to its `Member`.
    struct References {
        var callSites: [CallSite] = []
        var assignments: [VariableAssignment] = []
        var fieldReads: [FieldAccess] = []
        var referencedTypeNames: [String] = []
        var cyclomaticComplexity: Int?
    }

    /// The pieces a field's initializer contributes.
    struct ValueReferences {
        var callSites: [CallSite] = []
        var initialValue: VariableAssignment.Value?
        var referencedTypeNames: [String] = []
    }

    // MARK: - Method Declaration

    func methodDeclaration(
        _ node: Node,
        modifierInfo: ModifierInfo,
        generics: [GenericParameter],
        parameters: [Parameter],
        returnType: TypeReference?,
        references: References
    ) -> Member? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = nameNode.text(in: context)
        guard !name.isEmpty else { return nil }

        return Member(
            name: name, kind: .method,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            type: returnType, parameters: parameters, genericParameters: generics,
            annotations: modifierInfo.annotations, location: node.location(in: context),
            callSites: references.callSites,
            assignments: references.assignments,
            fieldReads: references.fieldReads,
            referencedTypeNames: references.referencedTypeNames,
            cyclomaticComplexity: references.cyclomaticComplexity
        )
    }

    // MARK: - Constructor Declaration

    func constructorDeclaration(
        _ node: Node,
        modifierInfo: ModifierInfo,
        generics: [GenericParameter],
        parameters: [Parameter],
        references: References
    ) -> Member {
        let name = node.child(byFieldName: "name").map { $0.text(in: context) } ?? ""

        return Member(
            name: name, kind: .initializer,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            parameters: parameters, genericParameters: generics,
            annotations: modifierInfo.annotations, location: node.location(in: context),
            callSites: references.callSites,
            assignments: references.assignments,
            fieldReads: references.fieldReads,
            referencedTypeNames: references.referencedTypeNames,
            cyclomaticComplexity: references.cyclomaticComplexity
        )
    }

    // MARK: - Field Declaration (one variable_declarator)

    func fieldMember(
        _ declaratorNode: Node,
        fieldType: TypeReference?,
        modifierInfo: ModifierInfo,
        location: SourceLocation,
        references: ValueReferences
    ) -> Member? {
        guard let nameNode = declaratorNode.child(byFieldName: "name") else { return nil }
        let name = nameNode.text(in: context)
        guard !name.isEmpty else { return nil }

        var actualType = fieldType
        if let dimensionsNode = declaratorNode.child(byFieldName: "dimensions") {
            let dimText = dimensionsNode.text(in: context)
            let bracketPairs = dimText.components(separatedBy: "[]").count - 1
            if bracketPairs > 0, let arrayFieldType = actualType {
                actualType = TypeReference(
                    name: arrayFieldType.name, genericArguments: arrayFieldType.genericArguments,
                    isOptional: arrayFieldType.isOptional, isArray: true
                )
            }
        }

        return Member(
            name: name, kind: .property,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            type: actualType, annotations: modifierInfo.annotations, location: location,
            callSites: references.callSites,
            initialValue: references.initialValue,
            referencedTypeNames: references.referencedTypeNames
        )
    }

    // MARK: - Annotation Type Element

    func annotationTypeElement(_ node: Node, modifierInfo: ModifierInfo, returnType: TypeReference?) -> Member? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = nameNode.text(in: context)
        guard !name.isEmpty else { return nil }

        return Member(
            name: name, kind: .method,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            type: returnType, annotations: modifierInfo.annotations, location: node.location(in: context)
        )
    }
}
