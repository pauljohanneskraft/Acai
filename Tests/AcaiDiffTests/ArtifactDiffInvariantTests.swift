import Testing
import AcaiArtifactGenerator
import AcaiCore
@testable import AcaiDiff

/// Properties `ArtifactDiffer` must satisfy for *every* pair of artifacts, checked over seeded random
/// ones. A failure reports its seed; replay it with `ArtifactGenerator(seed:)`.
@Suite("Artifact diff invariants", .timeLimit(.minutes(1)))
struct ArtifactDiffInvariantTests {
    private let differ = ArtifactDiffer()

    @Test("An artifact against itself is an empty diff")
    func diffingAnArtifactWithItselfIsEmpty() {
        for seed in ArtifactInvariantSeeds.standard.seeds {
            let artifact = ArtifactGenerator(seed: seed).makeArtifact()
            let diff = differ.diff(old: artifact, new: artifact)
            #expect(diff.isEmpty, "self-diff is not empty for seed \(seed)")
        }
    }

    @Test("Swapping the two sides mirrors added and removed")
    func swappingSidesMirrorsAddedAndRemoved() {
        for (old, new, label) in ArtifactInvariantSeeds.standard.pairs {
            let forward = differ.diff(old: old, new: new)
            let backward = differ.diff(old: new, new: old)

            #expect(forward.addedTypes == backward.removedTypes, "types not mirrored for \(label)")
            #expect(forward.removedTypes == backward.addedTypes, "types not mirrored for \(label)")
            #expect(
                forward.addedRelationships.map(\.diffKey).sorted()
                    == backward.removedRelationships.map(\.diffKey).sorted(),
                "relationships not mirrored for \(label)"
            )
            #expect(
                forward.removedRelationships.map(\.diffKey).sorted()
                    == backward.addedRelationships.map(\.diffKey).sorted(),
                "relationships not mirrored for \(label)"
            )
            // A change is symmetric in *which* elements moved, with the two sides transposed.
            #expect(
                forward.changedTypes.map(\.id) == backward.changedTypes.map(\.id),
                "changed types not mirrored for \(label)"
            )
            #expect(
                forward.changedRelationships.map(\.before.diffKey).sorted()
                    == backward.changedRelationships.map(\.after.diffKey).sorted(),
                "changed relationships not transposed for \(label)"
            )
            for change in forward.changedTypes {
                let mirrored = backward.changedTypes.first { $0.id == change.id }
                #expect(change.kindChange?.before == mirrored?.kindChange?.after, "\(label) \(change.id)")
                #expect(change.kindChange?.after == mirrored?.kindChange?.before, "\(label) \(change.id)")
                #expect(
                    change.addedMembers.sorted() == (mirrored?.removedMembers ?? []).sorted(),
                    "members not mirrored for \(label) \(change.id)"
                )
                #expect(
                    change.removedMembers.sorted() == (mirrored?.addedMembers ?? []).sorted(),
                    "members not mirrored for \(label) \(change.id)"
                )
            }
        }
    }

    @Test("The union carries every type and edge from both sides")
    func theUnionCarriesEverythingFromBothSides() {
        for (old, new, label) in ArtifactInvariantSeeds.standard.pairs {
            let union = differ.unionArtifact(old: old, new: new)
            let unionIDs = Set(union.flattened().map(\.id))
            #expect(unionIDs.isSuperset(of: old.flattened().map(\.id)), "union lost an old type for \(label)")
            #expect(unionIDs.isSuperset(of: new.flattened().map(\.id)), "union lost a new type for \(label)")

            let unionKeys = Set(union.relationships.map(\.diffKey))
            #expect(unionKeys.isSuperset(of: old.relationships.map(\.diffKey)), "union lost an old edge for \(label)")
            #expect(unionKeys.isSuperset(of: new.relationships.map(\.diffKey)), "union lost a new edge for \(label)")
        }
    }

    @Test("Every diffed element classifies as exactly what the diff says it is")
    func statusMatchesTheDiffLists() {
        for (old, new, label) in ArtifactInvariantSeeds.standard.pairs {
            let diff = differ.diff(old: old, new: new)
            let typeStatus = diff.typeStatusLookup()
            let relationshipStatus = diff.relationshipStatusLookup()

            for id in diff.addedTypes {
                #expect(diff.status(ofType: id) == .added, "\(label) \(id)")
                #expect(typeStatus(id) == .added, "the fast lookup disagrees for \(label) \(id)")
            }
            for id in diff.removedTypes {
                #expect(diff.status(ofType: id) == .removed, "\(label) \(id)")
                #expect(typeStatus(id) == .removed, "the fast lookup disagrees for \(label) \(id)")
            }
            for relationship in diff.addedRelationships {
                #expect(relationshipStatus(relationship) == diff.status(of: relationship), "\(label)")
            }
        }
    }
}

private extension ArtifactInvariantSeeds {
    /// Consecutive seeds paired up, so each comparison is between two genuinely different artifacts
    /// rather than two shapes of the same one.
    var pairs: [(old: CodeArtifact, new: CodeArtifact, label: String)] {
        stride(from: 0, to: seeds.count - 1, by: 2).map { index in
            let (first, second) = (seeds[index], seeds[index + 1])
            return (
                ArtifactGenerator(seed: first).makeArtifact(),
                ArtifactGenerator(seed: second).makeArtifact(),
                "seeds \(first) and \(second)"
            )
        }
    }
}
