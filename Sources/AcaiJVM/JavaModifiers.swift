import AcaiCore
import AcaiTreeSitter

// MARK: - JavaModifiers

/// Reads a Java declaration's `modifiers` node into a `ModifierInfo`. Stateless beyond `context`.
struct JavaModifiers {
    let context: SourceFileContext

    private static let accessLevelMap: [String: AccessLevel] = [
        "public": .public, "private": .private, "protected": .protected
    ]
    private static let modifierMap: [String: Modifier] = [
        "static": .static, "final": .final, "abstract": .abstract,
        "synchronized": .synchronized, "volatile": .volatile,
        "transient": .transient, "native": .native,
        "strictfp": .strictfp, "default": .default
    ]

    // Java's default (no explicit modifier) is package-private — resolved here so the engine never
    // sees a nil visibility. `@Override` maps to the `.override` modifier, so the dead-code scan
    // exempts an override of a supertype/interface member the same way it does for other languages.
    private static let classifier = ModifierClassifier(
        defaultAccessLevel: .packagePrivate,
        annotationNodeTypes: ["marker_annotation", "annotation"],
        classify: { nodeType, _ in
            if let access = accessLevelMap[nodeType] { return .accessLevel(access) }
            if let modifier = modifierMap[nodeType] { return .modifier(modifier) }
            return nil
        },
        postProcess: { info in
            let hasOverrideAnnotation = info.annotations.contains { $0.lowercased() == "@override" }
            if !info.modifiers.contains(.override), hasOverrideAnnotation {
                info.modifiers.append(.override)
            }
        }
    )

    func info(for node: Node) -> ModifierInfo {
        Self.classifier.modifierInfo(for: node, in: context)
    }

    /// Reads the declaration's own `modifiers` child, if any.
    func info(fromParentOf node: Node) -> ModifierInfo {
        if let modifiersNode = node.firstChild(withType: "modifiers") {
            return info(for: modifiersNode)
        }
        return ModifierInfo(accessLevel: .packagePrivate, modifiers: [], annotations: [])
    }
}
