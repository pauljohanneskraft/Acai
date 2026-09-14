import AcaiCore

// MARK: - ModifierClassifier

/// Builds a ``ModifierInfo`` by walking a declaration's `modifiers` node and classifying each child
/// via a language-supplied lookup. Java and Kotlin each did this with their own hand-rolled loop that
/// turned out to be the same shape — walk children, and for each one decide access level vs. modifier
/// vs. annotation — differing only in which node types/keywords mean what, which is exactly the kind
/// of difference `classify` and `annotationNodeTypes` exist to carry.
public struct ModifierClassifier: Sendable {
    public enum Classification {
        case accessLevel(AccessLevel)
        case modifier(Modifier)
    }

    private let defaultAccessLevel: AccessLevel
    private let annotationNodeTypes: Set<String>
    private let classify: @Sendable (_ nodeType: String, _ text: String) -> Classification?
    private let postProcess: @Sendable (inout ModifierInfo) -> Void

    /// - Parameters:
    ///   - defaultAccessLevel: Used when no child classifies as an access level (a language's implicit
    ///     visibility, e.g. Java's package-private or Kotlin's public).
    ///   - annotationNodeTypes: Child node types collected verbatim as annotations (normalized with a
    ///     leading `@`) rather than passed to `classify`.
    ///   - classify: Maps a non-annotation child's node type and text to an access level or modifier;
    ///     `nil` for anything else (punctuation, unrelated children).
    ///   - postProcess: Applied after the walk, for a rule that depends on the assembled result rather
    ///     than a single child (e.g. Java's implicit `.override` from an `@Override` annotation).
    public init(
        defaultAccessLevel: AccessLevel,
        annotationNodeTypes: Set<String>,
        classify: @escaping @Sendable (_ nodeType: String, _ text: String) -> Classification?,
        postProcess: @escaping @Sendable (inout ModifierInfo) -> Void = { _ in }
    ) {
        self.defaultAccessLevel = defaultAccessLevel
        self.annotationNodeTypes = annotationNodeTypes
        self.classify = classify
        self.postProcess = postProcess
    }

    /// `node` is the declaration's `modifiers` node itself — `nil` when the declaration has none,
    /// which yields `defaultAccessLevel` with no modifiers or annotations.
    public func modifierInfo(for node: Node?, in context: SourceFileContext) -> ModifierInfo {
        guard let node else { return ModifierInfo(accessLevel: defaultAccessLevel) }

        var accessLevel: AccessLevel?
        var modifiers: [Modifier] = []
        var annotations: [String] = []

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            let childText = child.text(in: context)

            if annotationNodeTypes.contains(nodeType) {
                annotations.append(childText.hasPrefix("@") ? childText : "@\(childText)")
                continue
            }

            switch classify(nodeType, childText) {
            case .accessLevel(let level):
                accessLevel = level
            case .modifier(let modifier):
                modifiers.append(modifier)
            case nil:
                break
            }
        }

        var info = ModifierInfo(
            accessLevel: accessLevel ?? defaultAccessLevel, modifiers: modifiers, annotations: annotations
        )
        postProcess(&info)
        return info
    }
}
