import AcaiCore

/// Computes the structural delta between two `CodeArtifact` revisions.
///
/// Both inputs should be `enriched()` (relationship endpoints resolved to canonical type ids,
/// structural edges inferred) so the two sides are compared on equal footing; stored analyses
/// produced by `analyze`/`store` already are. Every output array is sorted, so the diff is
/// deterministic and its JSON is byte-stable.
public struct ArtifactDiffer: Sendable {
    private let moduleResolver: ModuleResolver

    public init(moduleResolver: ModuleResolver = .standard) {
        self.moduleResolver = moduleResolver
    }

    public func diff(old: CodeArtifact, new: CodeArtifact) -> ArtifactDiff {
        let oldTypes = old.flattened()
        let newTypes = new.flattened()
        let identities = TypeIdentities(old: oldTypes, new: newTypes, moduleResolver: moduleResolver)
        let oldByIdentity = Dictionary(
            oldTypes.map { (identities.old.identity(of: $0.id), $0) }, uniquingKeysWith: { first, _ in first })
        let newByIdentity = Dictionary(
            newTypes.map { (identities.new.identity(of: $0.id), $0) }, uniquingKeysWith: { first, _ in first })

        let addedTypes = newByIdentity.filter { oldByIdentity[$0.key] == nil }.map(\.value.id).sorted()
        let removedTypes = oldByIdentity.filter { newByIdentity[$0.key] == nil }.map(\.value.id).sorted()
        let changedTypes = newByIdentity.compactMap { identity, newType -> TypeChange? in
            guard let oldType = oldByIdentity[identity] else { return nil }
            return typeChange(id: newType.id, old: oldType, new: newType)
        }.sorted { $0.id < $1.id }

        let (added, removed, changed) = relationshipDiff(
            old: old.relationships, new: new.relationships, identities: identities)

        let oldMetrics = old.computeMetrics()
        let newMetrics = new.computeMetrics()

        return ArtifactDiff(
            types: TypeDelta(added: addedTypes, removed: removedTypes, changed: changedTypes),
            relationships: RelationshipDelta(added: added, removed: removed, changed: changed),
            metrics: MetricDelta(
                modules: moduleMetricDeltas(old: oldMetrics, new: newMetrics),
                types: typeMetricDeltas(old: oldMetrics, new: newMetrics)),
            functions: memberDelta(old: old.freestandingFunctions, new: new.freestandingFunctions),
            globals: memberDelta(old: old.globalVariables, new: new.globalVariables)
        )
    }

    /// The union of two revisions as a single artifact for rendering a delta diagram: every type,
    /// relationship and free declaration from both sides, so removed elements appear alongside added
    /// and unchanged ones and a caller can tint each by `ArtifactDiff.status(of:)`. The new side
    /// wins wherever both declare the same element, matched by ``TypeIdentities`` rather than by id
    /// — otherwise a re-scoped id puts the same type, and the same edge, in twice.
    public func unionArtifact(old: CodeArtifact, new: CodeArtifact) -> CodeArtifact {
        let newFlat = new.flattened()
        let oldFlat = old.flattened()
        let identities = TypeIdentities(old: oldFlat, new: newFlat, moduleResolver: moduleResolver)
        let newIdentities = Set(newFlat.map { identities.new.identity(of: $0.id) })
        let removedTypes = oldFlat.filter { !newIdentities.contains(identities.old.identity(of: $0.id)) }
        let types = newFlat + removedTypes

        var seenKeys = Set(new.relationships.map { identities.new.key(of: $0) })
        var relationships = new.relationships
        for rel in old.relationships where seenKeys.insert(identities.old.key(of: rel)).inserted {
            relationships.append(rel)
        }

        return CodeArtifact(
            metadata: new.metadata,
            types: types.sorted { $0.id < $1.id },
            relationships: relationships.sorted { $0.diffKey < $1.diffKey },
            freestandingFunctions: union(new.freestandingFunctions, old.freestandingFunctions),
            globalVariables: union(new.globalVariables, old.globalVariables)
        )
    }

    /// `preferred` first, then every declaration of `other` whose signature it does not already
    /// carry — so a removed free function survives into the delta diagram.
    private func union(_ preferred: [Member], _ other: [Member]) -> [Member] {
        var seen = Set(preferred.map(\.diffSignature))
        return preferred + other.filter { seen.insert($0.diffSignature).inserted }
    }

    // MARK: - Types

    private func typeChange(id: String, old: TypeDeclaration, new: TypeDeclaration) -> TypeChange? {
        let kindChange = old.kind == new.kind ? nil : Change(before: old.kind, after: new.kind)
        let accessChange = old.accessLevel == new.accessLevel
            ? nil : Change(before: old.accessLevel, after: new.accessLevel)
        let members = memberDelta(old: old.members, new: new.members)

        guard kindChange != nil || accessChange != nil || !members.isEmpty else { return nil }

        return TypeChange(
            id: id,
            kindChange: kindChange,
            accessChange: accessChange,
            addedMembers: members.added,
            removedMembers: members.removed,
            changedMembers: members.changed
        )
    }

    // MARK: - Members

    /// Set-differences two flat member lists by signature, then pairs what is left by name. Used for
    /// a type's members and for an artifact's free functions and module-scope variables alike.
    private func memberDelta(old: [Member], new: [Member]) -> MemberDelta {
        let oldSignatures = Set(old.map(\.diffSignature))
        let newSignatures = Set(new.map(\.diffSignature))
        var addedSignatures = newSignatures.subtracting(oldSignatures)
        var removedSignatures = oldSignatures.subtracting(newSignatures)

        let changed = pairedMemberChanges(
            oldMembers: old.filter { removedSignatures.contains($0.diffSignature) },
            newMembers: new.filter { addedSignatures.contains($0.diffSignature) }
        )
        for change in changed {
            removedSignatures.remove(change.before)
            addedSignatures.remove(change.after)
        }

        return MemberDelta(
            added: addedSignatures.sorted(),
            removed: removedSignatures.sorted(),
            changed: changed.sorted { $0.name < $1.name }
        )
    }

    /// Pairs unmatched members by name so a retyped/re-accessed member reads as one change, not
    /// add+remove. Skips names with more than one unmatched candidate per side — overloads have no
    /// reliable correspondence.
    private func pairedMemberChanges(oldMembers: [Member], newMembers: [Member]) -> [MemberChange] {
        let oldByName = Dictionary(grouping: oldMembers, by: \.name)
        let newByName = Dictionary(grouping: newMembers, by: \.name)
        return oldByName.compactMap { name, olds -> MemberChange? in
            guard olds.count == 1, let news = newByName[name], news.count == 1 else { return nil }
            return MemberChange(name: name, before: olds[0].diffSignature, after: news[0].diffSignature)
        }
    }

    // MARK: - Relationships

    private func relationshipDiff(
        old: [Relationship], new: [Relationship], identities: TypeIdentities
    ) -> (added: [Relationship], removed: [Relationship], changed: [RelationshipChange]) {
        let oldByKey = Dictionary(
            old.map { (identities.old.key(of: $0), $0) }, uniquingKeysWith: { first, _ in first })
        let newByKey = Dictionary(
            new.map { (identities.new.key(of: $0), $0) }, uniquingKeysWith: { first, _ in first })

        let oldKeys = Set(oldByKey.keys)
        let newKeys = Set(newByKey.keys)

        let added = newByKey.filter { !oldKeys.contains($0.key) }.map(\.value)
        let removed = oldByKey.filter { !newKeys.contains($0.key) }.map(\.value)
        let changed = newByKey.compactMap { key, after -> RelationshipChange? in
            guard let before = oldByKey[key], before.labelSignature != after.labelSignature else { return nil }
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
    /// A stable signature for set-difference diffing, covering access level, `static`/`class`,
    /// kind, name, parameter labels + types and return type — without the labels, `move(to:)` and
    /// `move(from:)` collide; without access, a `public`→`private` change is invisible.
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
