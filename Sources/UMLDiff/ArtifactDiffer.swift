import UMLCore

/// Computes the structural delta between two `CodeArtifact` revisions.
///
/// Both inputs should be `enriched()` (relationship endpoints resolved to canonical type ids,
/// structural edges inferred) so the two sides are compared on equal footing. Stored analyses
/// produced by `analyze`/`store` are already enriched. The differ names no language: identity is
/// the canonical `TypeDeclaration.id` for nodes and `(source, target, kind)` for edges. Every
/// output array is sorted, so the diff is deterministic and its JSON is byte-stable.
public struct ArtifactDiffer: Sendable {
    private let moduleResolver: ModuleResolver

    public init(moduleResolver: ModuleResolver = .standard) {
        self.moduleResolver = moduleResolver
    }

    public func diff(old: CodeArtifact, new: CodeArtifact) -> ArtifactDiff {
        let oldTypes = old.flattened()
        let newTypes = new.flattened()
        let oldByID = Dictionary(oldTypes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newByID = Dictionary(newTypes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let oldIDs = Set(oldByID.keys)
        let newIDs = Set(newByID.keys)

        let addedTypes = newIDs.subtracting(oldIDs).sorted()
        let removedTypes = oldIDs.subtracting(newIDs).sorted()
        let changedTypes = newIDs.intersection(oldIDs).compactMap { id -> TypeChange? in
            typeChange(id: id, old: oldByID[id]!, new: newByID[id]!)
        }.sorted { $0.id < $1.id }

        let (added, removed, changed) = relationshipDiff(old: old.relationships, new: new.relationships)

        let oldMetrics = old.computeMetrics()
        let newMetrics = new.computeMetrics()

        return ArtifactDiff(
            addedTypes: addedTypes,
            removedTypes: removedTypes,
            changedTypes: changedTypes,
            addedRelationships: added,
            removedRelationships: removed,
            changedRelationships: changed,
            moduleMetricDeltas: moduleMetricDeltas(old: oldMetrics, new: newMetrics),
            typeMetricDeltas: typeMetricDeltas(old: oldMetrics, new: newMetrics)
        )
    }

    /// The union of two revisions as a single artifact for rendering a delta diagram: every type
    /// from both sides (new wins on id collision) and every relationship from both sides (deduped by
    /// (source, target, kind), new wins). Removed types/edges thus appear alongside added and
    /// unchanged ones, so a caller can tint each by `ArtifactDiff.status(of:)`.
    public func unionArtifact(old: CodeArtifact, new: CodeArtifact) -> CodeArtifact {
        let newFlat = new.flattened()
        let newIDs = Set(newFlat.map(\.id))
        let removedTypes = old.flattened().filter { !newIDs.contains($0.id) }
        let types = newFlat + removedTypes

        var seenKeys = Set(new.relationships.map(\.diffKey))
        var relationships = new.relationships
        for rel in old.relationships where seenKeys.insert(rel.diffKey).inserted {
            relationships.append(rel)
        }

        return CodeArtifact(
            metadata: new.metadata,
            types: types.sorted { $0.id < $1.id },
            relationships: relationships.sorted { $0.diffKey < $1.diffKey },
            freestandingFunctions: new.freestandingFunctions,
            globalVariables: new.globalVariables
        )
    }

    // MARK: - Types

    private func typeChange(id: String, old: TypeDeclaration, new: TypeDeclaration) -> TypeChange? {
        let kindChange = old.kind == new.kind ? nil : Change(before: old.kind, after: new.kind)
        let accessChange = old.accessLevel == new.accessLevel
            ? nil : Change(before: old.accessLevel, after: new.accessLevel)

        let oldSignatures = Set(old.members.map(\.diffSignature))
        let newSignatures = Set(new.members.map(\.diffSignature))
        let addedMembers = newSignatures.subtracting(oldSignatures).sorted()
        let removedMembers = oldSignatures.subtracting(newSignatures).sorted()

        guard kindChange != nil || accessChange != nil
            || !addedMembers.isEmpty || !removedMembers.isEmpty
        else { return nil }

        return TypeChange(
            id: id,
            kindChange: kindChange,
            accessChange: accessChange,
            addedMembers: addedMembers,
            removedMembers: removedMembers
        )
    }

    // MARK: - Relationships

    private func relationshipDiff(
        old: [Relationship], new: [Relationship]
    ) -> (added: [Relationship], removed: [Relationship], changed: [RelationshipChange]) {
        let oldByKey = Dictionary(old.map { ($0.diffKey, $0) }, uniquingKeysWith: { first, _ in first })
        let newByKey = Dictionary(new.map { ($0.diffKey, $0) }, uniquingKeysWith: { first, _ in first })

        let oldKeys = Set(oldByKey.keys)
        let newKeys = Set(newByKey.keys)

        let added = newByKey.filter { !oldKeys.contains($0.key) }.map(\.value)
        let removed = oldByKey.filter { !newKeys.contains($0.key) }.map(\.value)
        let changed = newByKey.compactMap { key, after -> RelationshipChange? in
            guard let before = oldByKey[key], before != after else { return nil }
            return RelationshipChange(before: before, after: after)
        }

        return (
            added: added.sorted { $0.diffKey < $1.diffKey },
            removed: removed.sorted { $0.diffKey < $1.diffKey },
            changed: changed.sorted { $0.after.diffKey < $1.after.diffKey }
        )
    }

    // MARK: - Metrics

    private func moduleMetricDeltas(old: CodeMetrics, new: CodeMetrics) -> [ModuleMetricDelta] {
        let oldByName = Dictionary(old.modules.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let newByName = Dictionary(new.modules.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        return Set(oldByName.keys).union(newByName.keys).sorted().compactMap { name in
            let before = oldByName[name]
            let after = newByName[name]
            let instability = Change(from: before?.instability, to: after?.instability)
            let abstractness = Change(from: before?.abstractness, to: after?.abstractness)
            let distance = Change(from: before?.distanceFromMainSequence, to: after?.distanceFromMainSequence)
            guard instability != nil || abstractness != nil || distance != nil else { return nil }
            return ModuleMetricDelta(
                module: name,
                instability: instability,
                abstractness: abstractness,
                distanceFromMainSequence: distance
            )
        }
    }

    private func typeMetricDeltas(old: CodeMetrics, new: CodeMetrics) -> [TypeMetricDelta] {
        let oldByID = Dictionary(old.types.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newByID = Dictionary(new.types.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return Set(oldByID.keys).union(newByID.keys).sorted().compactMap { id in
            let before = oldByID[id]
            let after = newByID[id]
            let fanIn = Change(from: before?.fanIn, to: after?.fanIn)
            let fanOut = Change(from: before?.fanOut, to: after?.fanOut)
            let dit = Change(from: before?.depthOfInheritance, to: after?.depthOfInheritance)
            guard fanIn != nil || fanOut != nil || dit != nil else { return nil }
            return TypeMetricDelta(id: id, fanIn: fanIn, fanOut: fanOut, depthOfInheritance: dit)
        }
    }

}

extension Member {
    /// A stable, human-readable signature for set-difference diffing. Includes access level,
    /// `static`/`class`, kind, name, parameter labels + types and return type, so an overload, a
    /// visibility change, or a signature change reads as add+remove rather than a silent edit.
    /// Without the labels, `move(to:)` and `move(from:)` collide; without access, a `public`→
    /// `private` change is invisible.
    var diffSignature: String {
        let params = parameters.map { param in
            let label = param.externalName ?? param.internalName
            return "\(label): \(param.type?.name ?? "_")"
        }.joined(separator: ", ")
        let returnType = type.map { ": \($0.name)" } ?? ""
        let access = "\(accessLevel.rawValue) "
        let staticPrefix = modifiers.contains(.static) || modifiers.contains(.class) ? "static " : ""
        return "\(access)\(staticPrefix)\(kind.rawValue) \(name)(\(params))\(returnType)"
    }
}
