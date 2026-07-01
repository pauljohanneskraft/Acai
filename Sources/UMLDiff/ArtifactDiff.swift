import UMLCore

/// The structural delta between two `CodeArtifact` revisions: only what changed, never the
/// unchanged bulk. Fully `Codable` so it can be emitted as a stable JSON changelog and consumed
/// by tooling, and it drives the delta diagram via `status(of:)`.
public struct ArtifactDiff: Codable, Equatable, Sendable {
    /// Canonical ids of types present only in the new revision.
    public var addedTypes: [String]
    /// Canonical ids of types present only in the old revision.
    public var removedTypes: [String]
    /// Types present in both revisions whose declaration changed.
    public var changedTypes: [TypeChange]

    /// Relationships present only in the new revision.
    public var addedRelationships: [Relationship]
    /// Relationships present only in the old revision.
    public var removedRelationships: [Relationship]
    /// Relationships present in both (same source/target/kind) with differing labels.
    public var changedRelationships: [RelationshipChange]

    /// Per-module coupling-metric changes (only modules whose metrics actually moved).
    public var moduleMetricDeltas: [ModuleMetricDelta]
    /// Per-type OO-metric changes (only types whose metrics actually moved).
    public var typeMetricDeltas: [TypeMetricDelta]

    public init(
        addedTypes: [String] = [],
        removedTypes: [String] = [],
        changedTypes: [TypeChange] = [],
        addedRelationships: [Relationship] = [],
        removedRelationships: [Relationship] = [],
        changedRelationships: [RelationshipChange] = [],
        moduleMetricDeltas: [ModuleMetricDelta] = [],
        typeMetricDeltas: [TypeMetricDelta] = []
    ) {
        self.addedTypes = addedTypes
        self.removedTypes = removedTypes
        self.changedTypes = changedTypes
        self.addedRelationships = addedRelationships
        self.removedRelationships = removedRelationships
        self.changedRelationships = changedRelationships
        self.moduleMetricDeltas = moduleMetricDeltas
        self.typeMetricDeltas = typeMetricDeltas
    }

    /// `true` when nothing structural changed between the two revisions. Metric-only movement
    /// still counts as a change (a refactor can shift coupling without adding/removing edges).
    public var isEmpty: Bool {
        addedTypes.isEmpty && removedTypes.isEmpty && changedTypes.isEmpty
            && addedRelationships.isEmpty && removedRelationships.isEmpty
            && changedRelationships.isEmpty
            && moduleMetricDeltas.isEmpty && typeMetricDeltas.isEmpty
    }

    /// The delta status of a relationship, keyed on (source, target, kind). Edges not part of the
    /// diff are `.unchanged`. Drives per-edge tinting in the delta diagram.
    public func status(of relationship: Relationship) -> DeltaStatus {
        let key = relationship.diffKey
        if addedRelationships.contains(where: { $0.diffKey == key }) { return .added }
        if removedRelationships.contains(where: { $0.diffKey == key }) { return .removed }
        if changedRelationships.contains(where: { $0.after.diffKey == key }) { return .changed }
        return .unchanged
    }

    /// The delta status of a type, keyed on its canonical id.
    public func status(ofType id: String) -> DeltaStatus {
        if addedTypes.contains(id) { return .added }
        if removedTypes.contains(id) { return .removed }
        if changedTypes.contains(where: { $0.id == id }) { return .changed }
        return .unchanged
    }

    /// An O(1) relationship-status lookup that pre-hashes the diff's edge keys once. For hot paths
    /// that classify *every* edge of the union diagram (delta rendering, redrawn each frame),
    /// building this once is O(N + M) instead of `status(of:)`'s O(N · M); `status(of:)` stays for
    /// one-off queries.
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

    /// An O(1) type-status lookup that pre-hashes the diff's type ids once — the node counterpart of
    /// `relationshipStatusLookup()` for hot paths that classify every node of the union diagram.
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
    /// This relationship's identity for diffing: source, target and kind. Labels are excluded so a
    /// label-only change reads as a `changed` edge rather than add+remove.
    var diffKey: String {
        "\(source)\u{1}\(target)\u{1}\(kind.rawValue)"
    }
}
