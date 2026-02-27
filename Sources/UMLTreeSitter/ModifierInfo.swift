import UMLCore

/// The result of extracting modifiers, access level, and annotations
/// from a tree-sitter `modifiers` (or equivalent) AST node.
///
/// Every language extractor produces this same structure, so it lives
/// in the shared `UMLTreeSitter` module. The `accessLevel` is optional
/// because some languages (e.g. Java) treat the absence of an explicit
/// modifier as a distinct visibility level (package-private / `nil`).
public struct ModifierInfo: Equatable, Sendable {
    public var accessLevel: AccessLevel?
    public var modifiers: [Modifier]
    public var annotations: [String]

    public init(
        accessLevel: AccessLevel? = nil,
        modifiers: [Modifier] = [],
        annotations: [String] = []
    ) {
        self.accessLevel = accessLevel
        self.modifiers = modifiers
        self.annotations = annotations
    }
}
