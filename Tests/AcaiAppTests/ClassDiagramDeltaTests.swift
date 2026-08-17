import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

@Suite("Class diagram delta mode")
@MainActor
struct ClassDiagramDeltaTests {

    private func type(_ name: String) -> TypeDeclaration {
        TypeDeclaration(id: name, name: name, qualifiedName: name, kind: .class,
                        accessLevel: .public,
                        location: SourceLocation(filePath: "Sources/App/\(name).swift", line: 1, column: 1))
    }

    private func artifact(_ types: [TypeDeclaration], _ rels: [Relationship]) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: CodeArtifact.SourceLanguage(rawValue: "swift")),
                     types: types, relationships: rels)
    }

    @Test func deltaColorsAddedAndRemovedEdgesButNotUnchanged() {
        let old = artifact([type("A"), type("B"), type("C"), type("D")], [
            Relationship(kind: .dependency, source: "A", target: "B"),
            Relationship(kind: .dependency, source: "A", target: "D")
        ])
        let new = artifact([type("A"), type("B"), type("C"), type("D")], [
            Relationship(kind: .dependency, source: "A", target: "B"),
            Relationship(kind: .dependency, source: "A", target: "C")
        ])
        let codebase = Codebase(name: "App", directoryPath: "/tmp/app")
        let viewModel = ClassDiagramViewModel(codebase: codebase, artifact: new, comparisonArtifact: old)

        #expect(viewModel.isDeltaMode)
        // The union includes A→B (unchanged), A→C (added), A→D (removed).
        let added = viewModel.edges.first { $0.sourceID == "A" && $0.targetID == "C" }
        let removed = viewModel.edges.first { $0.sourceID == "A" && $0.targetID == "D" }
        let unchanged = viewModel.edges.first { $0.sourceID == "A" && $0.targetID == "B" }
        #expect(added != nil && viewModel.deltaColor(for: added!) != nil)
        #expect(removed != nil && viewModel.deltaColor(for: removed!) != nil)
        #expect(unchanged != nil && viewModel.deltaColor(for: unchanged!) == nil)
    }

    @Test func noComparisonMeansNoDeltaColors() {
        let new = artifact([type("A"), type("B")], [Relationship(kind: .dependency, source: "A", target: "B")])
        let viewModel = ClassDiagramViewModel(codebase: Codebase(name: "App", directoryPath: "/tmp/app"),
                                              artifact: new)
        #expect(!viewModel.isDeltaMode)
        if let edge = viewModel.edges.first {
            #expect(viewModel.deltaColor(for: edge) == nil)
        }
    }

    private func widget(_ memberAccess: AccessLevel) -> TypeDeclaration {
        TypeDeclaration(id: "Widget", name: "Widget", qualifiedName: "Widget", kind: .class,
                        accessLevel: .public,
                        members: [Member(name: "value", kind: .property, accessLevel: memberAccess)],
                        location: SourceLocation(filePath: "Sources/App/Widget.swift", line: 1, column: 1))
    }

    @Test func deltaBadgeMatchesEachNodesStatusButNeverUnchanged() {
        let old = artifact([type("A"), widget(.public), type("C")], [])
        let new = artifact([type("A"), widget(.private), type("D")], [])
        let codebase = Codebase(name: "App", directoryPath: "/tmp/app")
        let viewModel = ClassDiagramViewModel(codebase: codebase, artifact: new, comparisonArtifact: old)

        let addedNode = viewModel.nodes.first { $0.id == "D" }
        let removedNode = viewModel.nodes.first { $0.id == "C" }
        let changedNode = viewModel.nodes.first { $0.id == "Widget" }
        let unchangedNode = viewModel.nodes.first { $0.id == "A" }

        #expect(addedNode.flatMap(viewModel.deltaBadge) == .added)
        #expect(removedNode.flatMap(viewModel.deltaBadge) == .removed)
        #expect(changedNode.flatMap(viewModel.deltaBadge) == .changed)
        #expect(unchangedNode.flatMap(viewModel.deltaBadge) == nil)
    }

    @Test func noComparisonMeansNoDeltaBadges() {
        let new = artifact([type("A")], [])
        let viewModel = ClassDiagramViewModel(codebase: Codebase(name: "App", directoryPath: "/tmp/app"),
                                              artifact: new)
        if let node = viewModel.nodes.first {
            #expect(viewModel.deltaBadge(for: node) == nil)
        }
    }

    @Test func typeChangeSurfacesTheFullMemberDetailReusingTheComputedDiff() throws {
        let old = artifact([widget(.public)], [])
        let new = artifact([widget(.private)], [])
        let codebase = Codebase(name: "App", directoryPath: "/tmp/app")
        let viewModel = ClassDiagramViewModel(codebase: codebase, artifact: new, comparisonArtifact: old)

        let node = try #require(viewModel.nodes.first { $0.id == "Widget" })
        let change = try #require(viewModel.typeChange(for: node))
        #expect(change.id == "Widget")
        let memberChange = try #require(change.changedMembers.first { $0.name == "value" })
        #expect(memberChange.before.contains("public"))
        #expect(memberChange.after.contains("private"))
    }

    @Test func typeChangeIsNilForUnchangedAddedAndRemovedNodes() {
        let old = artifact([type("A"), type("Gone")], [])
        let new = artifact([type("A"), type("New")], [])
        let codebase = Codebase(name: "App", directoryPath: "/tmp/app")
        let viewModel = ClassDiagramViewModel(codebase: codebase, artifact: new, comparisonArtifact: old)

        if let unchanged = viewModel.nodes.first(where: { $0.id == "A" }) {
            #expect(viewModel.typeChange(for: unchanged) == nil)
        }
        if let added = viewModel.nodes.first(where: { $0.id == "New" }) {
            #expect(viewModel.typeChange(for: added) == nil)
        }
        if let removed = viewModel.nodes.first(where: { $0.id == "Gone" }) {
            #expect(viewModel.typeChange(for: removed) == nil)
        }
    }
}
