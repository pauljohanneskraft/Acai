import AcaiCore

/// The structural delta between two `CodeArtifact` revisions: only what changed, never the
/// unchanged bulk. `Codable` so it can be emitted as a stable JSON changelog.
public struct ArtifactDiff: Codable, Equatable, Sendable {
    public var addedTypes: [String]
    public var removedTypes: [String]
    public var changedTypes: [TypeChange]

    public var addedRelationships: [Relationship]
    public var removedRelationships: [Relationship]
    public var changedRelationships: [RelationshipChange]

    public var moduleMetricDeltas: [ModuleMetricDelta]
    public var typeMetricDeltas: [TypeMetricDelta]

    public init(types: TypeDelta = .empty, relationships: RelationshipDelta = .empty, metrics: MetricDelta = .empty) {
        self.addedTypes = types.added
        self.removedTypes = types.removed
        self.changedTypes = types.changed
        self.addedRelationships = relationships.added
        self.removedRelationships = relationships.removed
        self.changedRelationships = relationships.changed
        self.moduleMetricDeltas = metrics.modules
        self.typeMetricDeltas = metrics.types
    }

    /// `true` only when nothing changed structurally *or* metrically — a refactor that shifts
    /// coupling without adding/removing anything still makes this `false`.
    public var isEmpty: Bool {
        addedTypes.isEmpty && removedTypes.isEmpty && changedTypes.isEmpty
            && addedRelationships.isEmpty && removedRelationships.isEmpty
            && changedRelationships.isEmpty
            && moduleMetricDeltas.isEmpty && typeMetricDeltas.isEmpty
    }

    public func status(of relationship: Relationship) -> DeltaStatus {
        let key = relationship.diffKey
        if addedRelationships.contains(where: { $0.diffKey == key }) { return .added }
        if removedRelationships.contains(where: { $0.diffKey == key }) { return .removed }
        if changedRelationships.contains(where: { $0.after.diffKey == key }) { return .changed }
        return .unchanged
    }

    public func status(ofType id: String) -> DeltaStatus {
        if addedTypes.contains(id) { return .added }
        if removedTypes.contains(id) { return .removed }
        if changedTypes.contains(where: { $0.id == id }) { return .changed }
        return .unchanged
    }

    public func typeChange(ofType id: String) -> TypeChange? {
        changedTypes.first { $0.id == id }
    }

    /// Pre-hashes the diff's edge keys once, for hot paths that classify every edge of the union
    /// diagram: O(N + M) total instead of calling `status(of:)` per edge at O(N · M).
    public func relationshipStatusLookup() -> @Sendable (Relationship) -> DeltaStatus {
        let added = Set(addedRelationships.map(\.diffKey))
        let removed = Set(removedRelationships.map(\.diffKey))
        let changed = Set(changedRelationships.map(\.after.diffKey))
        return { relationship in
            let key = relationship.diffKey
            if added.contains(key) { return .added }
            if removed.contains(key) { return .removed }
            if changed.contains(key) { return .changed }
            return .unchanged
        }
    }

    /// The node counterpart of `relationshipStatusLookup()`.
    public func typeStatusLookup() -> @Sendable (String) -> DeltaStatus {
        let added = Set(addedTypes)
        let removed = Set(removedTypes)
        let changed = Set(changedTypes.map(\.id))
        return { id in
            if added.contains(id) { return .added }
            if removed.contains(id) { return .removed }
            if changed.contains(id) { return .changed }
            return .unchanged
        }
    }
}

extension Relationship {
    /// Labels are excluded so a label-only change reads as `changed` rather than add+remove.
    var diffKey: String {
        "\(source)\u{1}\(target)\u{1}\(kind.rawValue)"
    }
}
