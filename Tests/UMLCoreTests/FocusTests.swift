import Testing
@testable import UMLCore

/// Tests for `CodeArtifact.focusedSubset` — single-class focus traversal and edge selection.
@Suite("Core: Single-Class Focus")
struct FocusTests {

    private func type(_ name: String, kind: TypeKind = .struct) -> TypeDeclaration {
        TypeDeclaration(id: name, name: name, qualifiedName: name, kind: kind, accessLevel: .internal)
    }

    private func rel(
        _ source: String, _ target: String, _ kind: Relationship.Kind = .dependency
    ) -> Relationship {
        Relationship(kind: kind, source: source, target: target)
    }

    /// A small graph (edges are *source depends on target*):
    ///   Root → DepA → DepB → DepC        (dependency chain)
    ///   Root → Base                       (inheritance)
    ///   Dependent1 → Root                 (Dependent1 depends on Root)
    ///   Dependent2 → Dependent1           (dependent of a dependent)
    ///   Dependent1 → DepA                 (cross link, never walked from Root)
    ///   Unrelated (isolated)
    private var types: [TypeDeclaration] {
        ["Root", "DepA", "DepB", "DepC", "Base", "Dependent1", "Dependent2", "Unrelated"]
            .map { type($0, kind: $0 == "Base" ? .protocol : .struct) }
    }
    private var relationships: [Relationship] {
        [
            rel("Root", "DepA"), rel("DepA", "DepB"), rel("DepB", "DepC"),
            rel("Root", "Base", .inheritance),
            rel("Dependent1", "Root"), rel("Dependent2", "Dependent1"),
            rel("Dependent1", "DepA")
        ]
    }

    private func focus(
        _ direction: FocusConfiguration.Direction,
        depth: Int? = nil,
        kinds: Set<Relationship.Kind> = Set(Relationship.Kind.allCases),
        interconnections: Bool = true
    ) -> (ids: Set<String>, pairs: Set<String>) {
        let config = FocusConfiguration(
            rootTypeName: "Root", maxDepth: depth, direction: direction,
            includedRelationshipKinds: kinds, includeInterconnections: interconnections
        )
        let result = CodeArtifact.focusedSubset(
            types: types, relationships: relationships, configuration: config
        )
        return (
            Set(result.types.map(\.id)),
            Set(result.relationships.map { "\($0.source)→\($0.target)" })
        )
    }

    @Test func dependenciesUnlimitedFollowsOutgoingOnly() {
        let result = focus(.dependencies)
        #expect(result.ids == ["Root", "DepA", "DepB", "DepC", "Base"])
    }

    @Test func depthOneKeepsOnlyDirectNeighbours() {
        let result = focus(.dependencies, depth: 1)
        #expect(result.ids == ["Root", "DepA", "Base"])
    }

    @Test func dependentsFollowIncomingOnlyAndNeverSwitchDirection() {
        // Dependent1 depends on Root and on DepA, but DepA must NOT appear: it is a
        // dependency of a dependent, reached only by switching direction mid-path.
        let result = focus(.dependents)
        #expect(result.ids == ["Root", "Dependent1", "Dependent2"])
    }

    @Test func bothUnionsTheTwoDirectionalWalks() {
        let result = focus(.both)
        #expect(result.ids == ["Root", "DepA", "DepB", "DepC", "Base", "Dependent1", "Dependent2"])
        #expect(!result.ids.contains("Unrelated"))
    }

    @Test func relationshipKindFilterRestrictsTraversal() {
        let result = focus(.dependencies, kinds: [.inheritance])
        #expect(result.ids == ["Root", "Base"])
    }

    @Test func interconnectionsDrawCrossLinksAmongSelectedNodes() {
        // Both Dependent1 and DepA are selected under `.both`; the cross link between them
        // is drawn only when interconnections are on, since the traversal never walked it.
        let withLinks = focus(.both, interconnections: true)
        #expect(withLinks.pairs.contains("Dependent1→DepA"))

        let walkedOnly = focus(.both, interconnections: false)
        #expect(!walkedOnly.pairs.contains("Dependent1→DepA"))
        #expect(walkedOnly.pairs.contains("Root→DepA"))
    }

    @Test func unresolvableRootYieldsEmptySubset() {
        let config = FocusConfiguration(rootTypeName: "DoesNotExist")
        let result = CodeArtifact.focusedSubset(
            types: types, relationships: relationships, configuration: config
        )
        #expect(result.types.isEmpty)
        #expect(result.relationships.isEmpty)
    }
}
