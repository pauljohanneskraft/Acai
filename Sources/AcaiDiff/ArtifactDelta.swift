import AcaiCore

// Grouped constructor parameters for ``ArtifactDiff``, so building one (its change lists stay flat
// for a stable JSON changelog) takes five arguments instead of fourteen.

public struct TypeDelta: Sendable {
    public var added: [String]
    public var removed: [String]
    public var changed: [TypeChange]

    public init(added: [String] = [], removed: [String] = [], changed: [TypeChange] = []) {
        self.added = added
        self.removed = removed
        self.changed = changed
    }

    public static let empty = TypeDelta()
}

public struct RelationshipDelta: Sendable {
    public var added: [Relationship]
    public var removed: [Relationship]
    public var changed: [RelationshipChange]

    public init(
        added: [Relationship] = [], removed: [Relationship] = [], changed: [RelationshipChange] = []
    ) {
        self.added = added
        self.removed = removed
        self.changed = changed
    }

    public static let empty = RelationshipDelta()
}

/// Added, removed and signature-changed declarations of one flat group — a type's members, or an
/// artifact's free functions or module-scope variables.
public struct MemberDelta: Sendable {
    /// Excludes members in `changed`.
    public var added: [String]
    /// Excludes members in `changed`.
    public var removed: [String]
    public var changed: [MemberChange]

    public init(added: [String] = [], removed: [String] = [], changed: [MemberChange] = []) {
        self.added = added
        self.removed = removed
        self.changed = changed
    }

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }

    public static let empty = MemberDelta()
}

public struct MetricDelta: Sendable {
    public var modules: [ModuleMetricDelta]
    public var types: [TypeMetricDelta]

    public init(modules: [ModuleMetricDelta] = [], types: [TypeMetricDelta] = []) {
        self.modules = modules
        self.types = types
    }

    public static let empty = MetricDelta()
}
