import Testing
import UMLCore
@testable import UMLDiff

@Suite("Diff: ArtifactDiffer")
struct ArtifactDifferTests {

    private func type(
        _ name: String, kind: TypeKind = .class, module: String = "App",
        access: AccessLevel = .internal, members: [Member] = []
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: kind,
            accessLevel: access, members: members,
            location: SourceLocation(filePath: "Sources/\(module)/\(name).swift", line: 1, column: 1))
    }

    private func artifact(_ types: [TypeDeclaration], _ rels: [Relationship] = []) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types, relationships: rels).enriched()
    }

    @Test func identicalArtifactsProduceEmptyDiff() {
        let a = artifact([type("Foo"), type("Bar")], [Relationship(kind: .dependency, source: "Foo", target: "Bar")])
        let diff = ArtifactDiffer().diff(old: a, new: a)
        #expect(diff.isEmpty)
    }

    @Test func detectsAddedAndRemovedTypes() {
        let old = artifact([type("Foo"), type("Bar")])
        let new = artifact([type("Foo"), type("Baz")])
        let diff = ArtifactDiffer().diff(old: old, new: new)
        #expect(diff.addedTypes == ["Baz"])
        #expect(diff.removedTypes == ["Bar"])
        #expect(diff.changedTypes.isEmpty)
    }

    @Test func detectsAddedAndRemovedRelationships() {
        // User→Account inheritance removed; OrderService→PaymentGateway dependency added.
        let old = artifact(
            [type("User"), type("Account"), type("OrderService"), type("PaymentGateway")],
            [Relationship(kind: .inheritance, source: "User", target: "Account")])
        let new = artifact(
            [type("User"), type("Account"), type("OrderService"), type("PaymentGateway")],
            [Relationship(kind: .dependency, source: "OrderService", target: "PaymentGateway")])
        let diff = ArtifactDiffer().diff(old: old, new: new)
        #expect(diff.addedRelationships.contains {
            $0.source == "OrderService" && $0.target == "PaymentGateway" && $0.kind == .dependency
        })
        #expect(diff.removedRelationships.contains {
            $0.source == "User" && $0.target == "Account" && $0.kind == .inheritance
        })
    }

    @Test func labelOnlyChangeIsAChangedRelationship() {
        let old = artifact([type("A"), type("B")],
                           [Relationship(kind: .aggregation, source: "A", target: "B", targetLabel: "1")])
        let new = artifact([type("A"), type("B")],
                           [Relationship(kind: .aggregation, source: "A", target: "B", targetLabel: "*")])
        let diff = ArtifactDiffer().diff(old: old, new: new)
        #expect(diff.addedRelationships.isEmpty)
        #expect(diff.removedRelationships.isEmpty)
        #expect(diff.changedRelationships.count == 1)
        #expect(diff.changedRelationships.first?.after.targetLabel == "*")
    }

    @Test func detectsChangedTypeKindAccessAndMembers() throws {
        let old = artifact([type("Widget", kind: .struct, access: .internal,
                                  members: [Member(name: "old", kind: .method, accessLevel: .internal)])])
        let new = artifact([type("Widget", kind: .class, access: .public,
                                  members: [Member(name: "new", kind: .method, accessLevel: .internal)])])
        let diff = ArtifactDiffer().diff(old: old, new: new)
        let change = try #require(diff.changedTypes.first)
        #expect(change.id == "Widget")
        #expect(change.kindChange?.before == .struct)
        #expect(change.kindChange?.after == .class)
        #expect(change.accessChange?.after == .public)
        #expect(change.addedMembers.contains { $0.contains("new") })
        #expect(change.removedMembers.contains { $0.contains("old") })
    }

    @Test func distinguishesOverloadsByArgumentLabel() throws {
        // `move(to:)` and `move(from:)` share parameter type `Point`; only the label differs, so the
        // signature must keep the label or the removal of one overload is lost in the member set.
        func move(_ label: String) -> Member {
            Member(name: "move", kind: .method, accessLevel: .internal,
                   parameters: [Parameter(externalName: label, internalName: "p", type: TypeReference(name: "Point"))])
        }
        let old = artifact([type("Mover", members: [move("to"), move("from")])])
        let new = artifact([type("Mover", members: [move("to")])])
        let change = try #require(ArtifactDiffer().diff(old: old, new: new).changedTypes.first)
        #expect(change.addedMembers.isEmpty)
        #expect(change.removedMembers.contains { $0.contains("from") })
    }

    @Test func detectsMemberVisibilityChange() throws {
        let old = artifact([type("Widget", members: [Member(name: "secret", kind: .method, accessLevel: .public)])])
        let new = artifact([type("Widget", members: [Member(name: "secret", kind: .method, accessLevel: .private)])])
        let change = try #require(ArtifactDiffer().diff(old: old, new: new).changedTypes.first)
        #expect(change.removedMembers.contains { $0.contains("public") })
        #expect(change.addedMembers.contains { $0.contains("private") })
    }

    @Test func reportsMetricDeltas() {
        // Adding a cross-type dependency shifts fan-in/out and module coupling.
        let old = artifact([type("A"), type("B")])
        let new = artifact([type("A"), type("B")],
                           [Relationship(kind: .dependency, source: "A", target: "B")])
        let diff = ArtifactDiffer().diff(old: old, new: new)
        #expect(diff.typeMetricDeltas.contains { $0.id == "A" && $0.fanOut?.after == 1 })
        #expect(diff.typeMetricDeltas.contains { $0.id == "B" && $0.fanIn?.after == 1 })
    }

    @Test func statusOfRelationshipClassifiesEdges() {
        let old = artifact([type("A"), type("B"), type("C")],
                           [Relationship(kind: .dependency, source: "A", target: "B")])
        let new = artifact([type("A"), type("B"), type("C")],
                           [Relationship(kind: .dependency, source: "A", target: "C")])
        let diff = ArtifactDiffer().diff(old: old, new: new)
        #expect(diff.status(of: Relationship(kind: .dependency, source: "A", target: "C")) == .added)
        #expect(diff.status(of: Relationship(kind: .dependency, source: "A", target: "B")) == .removed)
    }
}
