import AcaiCore
import AcaiTreeSitter

// MARK: - KotlinModifiers

/// Reads a Kotlin declaration's `modifiers` node into a `ModifierInfo`, and its `val`/`var`
/// binding keyword. Stateless beyond `context`.
struct KotlinModifiers {
    let context: SourceFileContext

    private static let visibilityMap: [String: AccessLevel] = [
        "public": .public, "private": .private,
        "protected": .protected, "internal": .internal
    ]

    /// Unified modifier map keyed by node type, then by keyword text.
    private static let modifierMapByNodeType: [String: [String: Modifier]] = [
        "class_modifier": [
            "data": .data, "sealed": .sealed, "abstract": .abstract,
            "inner": .inner, "value": .inline
        ],
        "member_modifier": [
            "override": .override, "lateinit": .lazy, "const": .const
        ],
        "property_modifier": [
            "const": .const
        ],
        "function_modifier": [
            "suspend": .suspend, "inline": .inline
        ],
        "inheritance_modifier": [
            "open": .open, "final": .final, "abstract": .abstract
        ]
    ]

    /// In Kotlin every declaration without an explicit visibility modifier is **public** by default,
    /// so the returned `accessLevel` falls back to `.public`.
    private static let classifier = ModifierClassifier(
        defaultAccessLevel: .public,
        annotationNodeTypes: ["annotation"],
        classify: { nodeType, text in
            if nodeType == "visibility_modifier" { return visibilityMap[text].map { .accessLevel($0) } }
            if let categoryMap = modifierMapByNodeType[nodeType], let modifier = categoryMap[text] {
                return .modifier(modifier)
            }
            return nil
        }
    )

    func info(for node: Node?) -> ModifierInfo {
        Self.classifier.modifierInfo(for: node, in: context)
    }

    /// Reads the declaration's own `modifiers` child, if any.
    func info(fromParentOf node: Node) -> ModifierInfo {
        info(for: node.firstChild(withType: "modifiers"))
    }

    /// Returns whether the node declares `val` or `var` via a `binding_pattern_kind` child.
    /// Tree-sitter-kotlin wraps `val`/`var` in `[binding_pattern_kind] → [val]`.
    func bindingKind(of node: Node) -> String? {
        guard let bindingPatternNode = node.firstChild(withType: "binding_pattern_kind") else { return nil }
        let bindingText = bindingPatternNode.text(in: context).trimmingCharacters(in: .whitespaces)
        return (bindingText == "val" || bindingText == "var") ? bindingText : nil
    }
}
