import AcaiCore

// Grouped constructor parameters for ``ArtifactDiff``, so building one (its eight change lists stay
// flat for a stable JSON changelog) takes three arguments instead of eight.

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

public struct MetricDelta: Sendable {
    public var modules: [ModuleMetricDelta]
    public var types: [TypeMetricDelta]

    public init(modules: [ModuleMetricDelta] = [], types: [TypeMetricDelta] = []) {
        self.modules = modules
        self.types = types
    }

    public static let empty = MetricDelta()
}
