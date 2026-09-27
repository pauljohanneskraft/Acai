import Foundation
import Testing
import AcaiArtifactGenerator
import AcaiCore
@testable import AcaiLibrary

/// Properties that must hold for *every* valid artifact, checked over seeded random ones rather than
/// the handful of shapes a hand-written fixture covers. A failure reports its seed; replay it with
/// `ArtifactGenerator(seed:)`.
@Suite("Artifact invariants", .timeLimit(.minutes(1)))
struct ArtifactInvariantTests {
    /// A real language's classification, not a test fixture: enrichment's primitive/collection
    /// handling is what makes a second pass a candidate for adding edges the first already added.
    private let configuration = SwiftCodeParser().configuration

    @Test("Enrichment is idempotent")
    func enrichmentIsIdempotent() {
        for seed in ArtifactInvariantSeeds.standard.seeds {
            let artifact = ArtifactGenerator(seed: seed).makeArtifact()
            let once = artifact.enriched(configuration: configuration)
            let twice = once.enriched(configuration: configuration)
            #expect(once == twice, "enrichment is not idempotent for seed \(seed)")
        }
    }

    @Test("Call-site receiver resolution is idempotent")
    func callSiteResolutionIsIdempotent() {
        for seed in ArtifactInvariantSeeds.standard.seeds {
            let artifact = ArtifactGenerator(seed: seed).makeArtifact()
                .enriched(configuration: configuration)
            let once = artifact.resolvingCallSiteReceivers()
            #expect(once == once.resolvingCallSiteReceivers(), "not idempotent for seed \(seed)")
        }
    }

    @Test("Encoding and decoding an artifact is the identity")
    func codingIsIdentity() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for seed in ArtifactInvariantSeeds.standard.seeds {
            let artifact = ArtifactGenerator(seed: seed).makeArtifact()
            for candidate in [artifact, artifact.enriched(configuration: configuration)] {
                let decoded = try JSONDecoder().decode(
                    CodeArtifact.self, from: try encoder.encode(candidate))
                #expect(decoded == candidate, "coding is not the identity for seed \(seed)")
            }
        }
    }

    /// Seed 190 first caught enrichment re-appending its ambiguous-reference diagnostics, and seed 1
    /// then caught the deeper cause: the edges `inferringStructuralEdges` synthesises were never
    /// resolved on the pass that created them, so a second pass diagnosed them for the first time.
    @Test("An ambiguous reference is diagnosed once, on the first pass", arguments: [UInt64(1), 190])
    func ambiguousReferencesAreDiagnosedOnceOnTheFirstPass(seed: UInt64) {
        let artifact = ArtifactGenerator(seed: seed).makeArtifact()
        let once = artifact.enriched(configuration: configuration)
        let ambiguous = once.metadata.parseDiagnostics.filter { $0.kind == .unresolvedReference }
        #expect(!ambiguous.isEmpty, "seed \(seed) no longer produces an ambiguous reference")
        #expect(once.metadata.parseDiagnostics == once.enriched(configuration: configuration)
            .metadata.parseDiagnostics)
    }

    @Test("Flattening keeps every type exactly once, under a unique id")
    func flatteningPreservesEveryTypeUnderAUniqueID() {
        for seed in ArtifactInvariantSeeds.standard.seeds {
            let artifact = ArtifactGenerator(seed: seed).makeArtifact()
            let flattened = artifact.flattened()
            #expect(
                flattened.count == Set(flattened.map(\.id)).count,
                "flattening produced a duplicate id for seed \(seed)"
            )
            #expect(
                flattened.count == artifact.declaredTypeCount,
                "flattening lost or duplicated a type for seed \(seed)"
            )
        }
    }
}

private extension CodeArtifact {
    /// Every declaration in the tree, counted without going through `flattened()` — the thing under
    /// test cannot also be the expectation.
    var declaredTypeCount: Int {
        func count(_ types: [TypeDeclaration]) -> Int {
            types.reduce(0) { $0 + 1 + count($1.nestedTypes) }
        }
        return count(types)
    }
}
