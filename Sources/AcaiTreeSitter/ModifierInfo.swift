import AcaiCore

/// The result of extracting modifiers, access level, and annotations
/// from a tree-sitter `modifiers` (or equivalent) AST node.
///
/// Every language extractor produces this same structure, so it lives
/// in the shared `AcaiTreeSitter` module. `accessLevel` is non-optional: each language extractor
/// resolves its own default when the source has no explicit modifier (Java → `packagePrivate`,
/// Kotlin → `public`), so the engine never sees a type or member without a visibility.
public struct ModifierInfo: Equatable, Sendable {
    public var accessLevel: AccessLevel
    public var modifiers: [Modifier]
    public var annotations: [String]

    public init(
        accessLevel: AccessLevel,
        modifiers: [Modifier] = [],
        annotations: [String] = []
    ) {
        self.accessLevel = accessLevel
        self.modifiers = modifiers
        self.annotations = annotations
    }
}
