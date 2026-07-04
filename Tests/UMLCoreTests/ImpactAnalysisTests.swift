import Testing
import Foundation
@testable import UMLCore

/// Covers `ImpactAnalysis`: transitive dependents are collected (reverse reachability), the root is
/// excluded, an unknown root is reported as not found, and depth bounds the walk.
@Suite("Core: ImpactAnalysis")
struct ImpactAnalysisTests {

    /// C → B → A (source depends on target). So A's dependents are B and C.
    private func chain() -> CodeArtifact {
        let types = ["A", "B", "C"].map { name in
            TypeDeclaration(
                id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
                location: SourceLocation(filePath: "\(name).swift", line: 1, column: 1))
        }
        let relationships = [
            Relationship(kind: .association, source: "B", target: "A"),
            Relationship(kind: .association, source: "C", target: "B")
        ]
        return CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types, relationships: relationships)
    }

    @Test func collectsTransitiveDependentsExcludingRoot() {
        let report = ImpactAnalysis(artifact: chain(), rootType: "A").report
        #expect(report.found)
        #expect(report.blastRadius == 2)
        #expect(report.dependents.map(\.id) == ["B", "C"])
        #expect(report.dependents.first?.location?.filePath == "B.swift")
    }

    @Test func depthBoundsTheWalk() {
        let report = ImpactAnalysis(artifact: chain(), rootType: "A", maxDepth: 1).report
        // Only the direct dependent B is within one hop.
        #expect(report.dependents.map(\.id) == ["B"])
    }

    @Test func unknownRootIsNotFound() {
        let report = ImpactAnalysis(artifact: chain(), rootType: "Nope").report
        #expect(!report.found)
        #expect(report.blastRadius == 0)
    }

    @Test func isolatedRootIsFoundWithNoDependents() {
        let report = ImpactAnalysis(artifact: chain(), rootType: "C").report
        #expect(report.found)
        #expect(report.dependents.isEmpty)
    }
}
