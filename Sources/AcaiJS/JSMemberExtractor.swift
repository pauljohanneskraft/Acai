import AcaiCore
import AcaiTreeSitter

// MARK: - JSMemberExtractor

/// Shapes a `Member` value from an already-parsed method/field/signature node plus its
/// already-resolved pieces (parameters, return type, call sites, assignments, field reads) — mirrors
/// `AcaiPython`'s `PythonMemberExtractor`: this never resolves a call site or reads `JSExtractor`'s
/// declaration state itself, it only builds the value from what the caller already computed.
struct JSMemberExtractor {
    let context: SourceFileContext
    let isTypeScript: Bool
    let typeReferences: JSTypeReferenceResolver
    let parameterExtractor: JSParameterExtractor

    /// JS/TS structural decision-point node types for cyclomatic complexity.
    static let branchNodeKinds: Set<String> = [
        "if_statement", "for_statement", "for_in_statement", "while_statement", "do_statement",
        "catch_clause", "switch_case"
    ]

    private static let methodKeywordModifiers: [String: Modifier] = [
        "static": .static, "async": .async, "override": .override
    ]

    /// Shared with ``prototypeMember(name:assignedValue:)`` (JS-only prototype pattern).
    static let functionNodeTypes: Set<String> = [
        "function_expression", "function", "arrow_function"
    ]

    /// Fully resolved pieces a method/function body contributes to its `Member`.
    struct References {
        var callSites: [CallSite] = []
        var assignments: [VariableAssignment] = []
        var fieldReads: [FieldAccess] = []
        var referencedTypeNames: [String] = []
        var cyclomaticComplexity: Int?
    }

    /// The pieces a field or global variable's initializer contributes.
    struct ValueReferences {
        var callSites: [CallSite] = []
        var initialValue: VariableAssignment.Value?
        var referencedTypeNames: [String] = []
    }

    private struct MethodSignatureInfo {
        var kind: MemberKind
        var accessLevel: AccessLevel?
        var modifiers: [Modifier]
        var isComputed: Bool
    }

    // MARK: - Method Definition

    func methodDefinition(
        _ node: Node,
        generics: [GenericParameter],
        parameters: [Parameter],
        returnType: TypeReference?,
        references: References
    ) -> Member {
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { $0.text(in: context) } ?? ""
        let annotations = decorators(node)
        let sig = methodKindAndModifiers(node, name: name)

        return Member(
            name: name.isEmpty ? "_anonymous" : name,
            kind: sig.kind,
            accessLevel: sig.accessLevel ?? .internal,
            modifiers: sig.modifiers,
            type: returnType,
            parameters: parameters,
            genericParameters: generics,
            isComputed: sig.isComputed,
            annotations: annotations,
            location: node.location(in: context),
            callSites: references.callSites,
            assignments: references.assignments,
            fieldReads: references.fieldReads,
            referencedTypeNames: references.referencedTypeNames,
            cyclomaticComplexity: references.cyclomaticComplexity
        )
    }

    private func methodKindAndModifiers(_ node: Node, name: String) -> MethodSignatureInfo {
        var kind: MemberKind = .method
        var modifiers: [Modifier] = []
        var isComputed = false

        for child in node.children() {
            let childText = child.text(in: context)
            if let modifier = Self.methodKeywordModifiers[childText] {
                modifiers.append(modifier)
            } else if childText == "get" || childText == "set" {
                isComputed = true
                kind = .property
            } else if childText == "abstract", isTypeScript {
                modifiers.append(.abstract)
            }
        }

        var accessLevel: AccessLevel?
        if isTypeScript { accessLevel = typeReferences.extractAccessibilityModifier(node) }
        if name.hasPrefix("#") { accessLevel = .private }
        if name == "constructor" { kind = .initializer }
        if isTypeScript, node.hasDirectChildText("readonly", in: context) {
            modifiers.append(.readonly)
        }

        return MethodSignatureInfo(kind: kind, accessLevel: accessLevel, modifiers: modifiers, isComputed: isComputed)
    }

    // MARK: - Decorators / Annotations

    func decorators(_ node: Node) -> [String] {
        var annotations: [String] = []
        for child in node.children() {
            guard child.nodeType == "decorator" else { continue }
            let fullText = child.text(in: context)
            if let parenIdx = fullText.firstIndex(of: "(") {
                annotations.append(String(fullText[fullText.startIndex..<parenIdx]))
            } else {
                annotations.append(fullText)
            }
        }
        return annotations
    }
}
