import AcaiCore

// Grouped constructor parameters for ``ArtifactDiff``. The diff stores its eight change lists flat (so
// its JSON changelog stays stable and every reader keeps its `.addedTypes` etc. accessor), but building
// one used to mean an eight-argument call — the long-parameter smell. These three cohesive values —
// the type changes, the relationship changes, and the metric movement — collapse that to three
// arguments at the single construction site. `.empty` vends a no-change value (a value, not a namespace).

/// The type-level changes between two revisions: ids added / removed and declarations that changed.
public struct TypeDelta: Sendable {
    public var added: [String]
    public var removed: [String]
    public var changed: [TypeChange]

    public init(added: [String] = [], removed: [String] = [], changed: [TypeChange] = []) {
        self.added = added
        self.removed = removed
        self.changed = changed
    }

    /// No type changed between the two revisions.
    public static let empty = TypeDelta()
}

/// The relationship-level changes between two revisions: edges added / removed and edges whose label
/// changed (same source/target/kind).
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

    /// No relationship changed between the two revisions.
    public static let empty = RelationshipDelta()
}

/// The metric movement between two revisions: per-module and per-type metric changes (only entries
/// whose metrics actually moved).
public struct MetricDelta: Sendable {
    public var modules: [ModuleMetricDelta]
    public var types: [TypeMetricDelta]

    public init(modules: [ModuleMetricDelta] = [], types: [TypeMetricDelta] = []) {
        self.modules = modules
        self.types = types
    }

    /// No metric moved between the two revisions.
    public static let empty = MetricDelta()
}
