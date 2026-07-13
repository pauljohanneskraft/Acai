import UMLCore

/// Per-language keyword data for structural assembly — the one place a flat lookup table is the
/// right tool, since (unlike node shape) keyword-to-model-case mapping has no positional ambiguity
/// for a query to resolve.
public struct TypeStructureVocabulary: Sendable {
    /// Captured `@type.kind` keyword text → `TypeKind` (e.g. `"class"` → `.class`).
    public var kindKeywords: [String: TypeKind]
    /// Captured `@type.modifier`/`@member.modifier` keyword text → `Modifier`.
    public var modifierKeywords: [String: Modifier]
    /// Captured `@type.access`/`@member.access` keyword text → `AccessLevel`.
    public var accessKeywords: [String: AccessLevel]
    /// The access level assumed when a declaration carries no explicit access keyword.
    public var defaultAccessLevel: AccessLevel

    public init(
        kindKeywords: [String: TypeKind],
        modifierKeywords: [String: Modifier],
        accessKeywords: [String: AccessLevel],
        defaultAccessLevel: AccessLevel
    ) {
        self.kindKeywords = kindKeywords
        self.modifierKeywords = modifierKeywords
        self.accessKeywords = accessKeywords
        self.defaultAccessLevel = defaultAccessLevel
    }
}
